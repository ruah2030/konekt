import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/service_type.dart';
import '../../../../core/providers/ticker.dart';
import '../../../../core/utils/countdown.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/payment_models.dart';
import '../providers/payment_flow.dart';

/// Récapitulatif : prix exact garanti (devis 10 min, ou frais arrêtés d'une opération carte),
/// ce que le porteur paie, ce que le bénéficiaire reçoit, contrôles et avertissements du serveur.
class QuoteScreen extends ConsumerStatefulWidget {
  const QuoteScreen({super.key});

  @override
  ConsumerState<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends ConsumerState<QuoteScreen> {
  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  Future<void> _confirm() async {
    final flow = ref.read(paymentFlowProvider);
    final q = flow.quote;
    if (q == null) return;
    final notifier = ref.read(paymentFlowProvider.notifier)..clearPinError();
    if (q.isExternal) {
      // Portefeuille mobile : pas de PIN, la validation se fait chez l'opérateur.
      await notifier.confirmExternal();
      if (!mounted) return;
      final s = ref.read(paymentFlowProvider);
      if (s.execution != null || s.review != null) context.go(Routes.processing);
      return;
    }
    if (q.path == PaymentPath.catalogCard && !ref.read(authControllerProvider).hasPin) {
      showToast(context, "Créez d'abord votre code secret dans Profil.");
      return;
    }
    await context.push(Routes.payPin);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(paymentFlowProvider);
    final q = flow.quote;
    if (q == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Récapitulatif')),
        body: flow.quoting
            ? const Center(child: CircularProgressIndicator())
            : flow.quoteError != null
            ? Padding(padding: const EdgeInsets.all(16), child: ErrorBlock(flow.quoteError!))
            : const EmptyState(message: 'Aucun devis en cours.'),
      );
    }
    final now = ref.watch(nowProvider);
    final expired = q.isExpired(now) || flow.needsRequote;
    final balance = q.isExternal ? null : ref.watch(balanceProvider).value;
    final short = balance != null && !q.isCardOperation && q.amountDebited > balance;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(paymentFlowProvider.notifier).abandon();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('quote-back'),
            tooltip: 'Retour',
            icon: const Icon(Symbols.arrow_back_rounded),
            onPressed: _back,
          ),
          title: const Text('Récapitulatif'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: CountdownChip(
                  key: const Key('quote-timer'),
                  label: expired ? 'Prix expiré' : 'Prix garanti · ${mmss(remaining(q.guaranteedUntil, now))}',
                  expired: expired,
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TotalCard(quote: q),
              const SizedBox(height: 16),
              InfoRowsCard(_rows(q, flow.request)),
              if (q.service == ServiceType.transfer && q.targetHolderName != null) ...[
                const SizedBox(height: 16),
                const _Warning(
                  'Vérifiez le nom et les 4 derniers chiffres de la carte : un transfert abouti ne se reprend pas.',
                ),
              ],
              if (q.service == ServiceType.payout) ...[
                const SizedBox(height: 16),
                const _Warning('Vérifiez le numéro avant de confirmer : un versement abouti ne peut pas être repris.'),
              ],
              for (final c in q.checks) ...[const SizedBox(height: 16), _CheckRow(c)],
              for (final w in q.warnings) ...[const SizedBox(height: 16), _Warning(w)],
              if (short) ...[
                const SizedBox(height: 16),
                _Warning(
                  'Solde insuffisant : il vous manque ${formatFcfa(q.amountDebited - balance)}. '
                  'Le paiement sera refusé par votre carte.',
                ),
              ],
              if (flow.quoteError != null) ...[const SizedBox(height: 16), ErrorBlock(flow.quoteError!)],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (expired)
                  OutlinedButton.icon(
                    key: const Key('quote-refresh'),
                    onPressed: flow.quoting ? null : () => ref.read(paymentFlowProvider.notifier).requote(),
                    icon: const Icon(Symbols.refresh_rounded, size: 20),
                    label: const Text('Prix expiré · Refaire le devis'),
                  )
                else
                  FilledButton(
                    key: const Key('quote-confirm'),
                    onPressed: flow.submitting ? null : _confirm,
                    child: flow.submitting
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: KColors.onPrimary),
                          )
                        : Text(q.isExternal ? 'Envoyer la demande de paiement' : 'Confirmer le paiement'),
                  ),
                const SizedBox(height: 10),
                OutlinedButton(
                  key: const Key('quote-edit'),
                  onPressed: _back,
                  child: const Text('Modifier la demande'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<InfoRow> _rows(PaymentQuote q, PaymentRequest? request) {
    final d = q.display;
    String fee() => q.fee > 0 ? formatFcfa(q.fee) : 'Aucun';
    final pays = InfoRow(
      q.isExternal ? 'Total prélevé' : 'Vous payez',
      formatFcfa(q.amountDebited),
      emphasis: true,
      key: const Key('quote-debited'),
    );
    final receives = InfoRow(
      q.service == ServiceType.topup ? 'Crédité sur la carte' : 'Le bénéficiaire reçoit',
      formatFcfa(q.amountCredited),
      key: const Key('quote-credited'),
    );
    return switch (q.service) {
      ServiceType.transfer => [
        if (q.targetHolderName != null)
          InfoRow(
            'Bénéficiaire',
            [q.targetHolderName, if (q.targetLast4 != null) '•••• ${q.targetLast4}'].join(' · '),
            key: const Key('quote-target'),
          ),
        receives,
        InfoRow('Frais', fee()),
        pays,
      ],
      ServiceType.payout => [
        if (request?.walletLabel != null) InfoRow('Portefeuille', request!.walletLabel!),
        if (q.beneficiary != null)
          InfoRow(
            q.beneficiary!.verified ? 'Bénéficiaire (vérifié)' : 'Bénéficiaire',
            [q.beneficiary!.name, q.beneficiary!.identifier].whereType<String>().join(' · '),
            key: const Key('quote-target'),
          )
        else if (request != null)
          InfoRow('Numéro', '${request.cardBody['phone']}'),
        receives,
        InfoRow('Frais', fee()),
        pays,
      ],
      ServiceType.topup => [
        receives,
        if (d['cardLast4'] != null) InfoRow('Carte', '${d['holderName'] ?? ''} · •••• ${d['cardLast4']}'),
        if (request?.walletLabel != null)
          InfoRow('Depuis', [request!.walletLabel, d['payerVerifiedName']].whereType<Object>().join(' · ')),
        InfoRow('Frais', fee()),
        pays,
      ],
      ServiceType.airtime || ServiceType.data => [
        if (d['productName'] != null) InfoRow('Offre', '${d['productName']}'),
        if (d['beneficiary'] != null) InfoRow('Numéro', '${d['beneficiary']}', key: const Key('quote-target')),
        InfoRow('Montant', formatFcfa(q.amount)),
        InfoRow('Frais', fee()),
        pays,
      ],
      ServiceType.elec => [
        if (d['customerName'] != null)
          InfoRow('Titulaire du compteur', '${d['customerName']}', key: const Key('quote-target')),
        if (d['meterNum'] != null) InfoRow('Compteur', '${d['meterNum']}'),
        if (d['estimatedKwh'] != null) InfoRow('Énergie estimée', '${d['estimatedKwh']} kWh'),
        InfoRow('Montant', formatFcfa(q.amount)),
        InfoRow('Frais', fee()),
        pays,
      ],
      ServiceType.cash => [
        if (d['beneficiaryContact'] != null)
          InfoRow('Code envoyé à', '${d['beneficiaryContact']}', key: const Key('quote-target')),
        if (d['expiresAt'] is String) InfoRow('Valable jusqu’à', _hhmm(DateTime.parse(d['expiresAt'] as String))),
        InfoRow('Montant retiré', formatFcfa(q.amountCredited)),
        InfoRow('Frais', fee()),
        pays,
      ],
      ServiceType.tv => [InfoRow('Montant', formatFcfa(q.amount)), InfoRow('Frais', fee()), pays],
    };
  }

  static String _hhmm(DateTime d) {
    final l = d.toLocal();
    return '${l.hour}h${l.minute.toString().padLeft(2, '0')}';
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.quote});
  final PaymentQuote quote;

  @override
  Widget build(BuildContext context) {
    const sub = Color(0xFFB8BCE8);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: KColors.primary, borderRadius: BorderRadius.circular(28)),
      child: Stack(
        children: [
          Positioned(
            right: -80,
            top: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x33F0B23A), Color(0x00F0B23A)], stops: [0, 0.7]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.service.title,
                  style: const TextStyle(fontSize: 14, color: sub, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Text(
                  quote.isExternal ? 'Total prélevé sur votre Mobile Money' : 'Total débité de votre carte',
                  style: const TextStyle(fontSize: 13, color: sub, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  formatFcfa(quote.amountDebited),
                  key: const Key('quote-total'),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    color: KColors.onPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.check);
  final QuoteCheck check;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(
            check.passed ? Symbols.check_circle_rounded : Symbols.cancel_rounded,
            fill: 1,
            size: 22,
            color: check.passed ? KColors.success : KColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: check.label,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: KColors.primary),
                  ),
                  if (check.detail != null) TextSpan(text: ' · ${check.detail}'),
                ],
              ),
              style: t.bodyMedium?.copyWith(color: const Color(0xFF334155), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(12)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Symbols.warning_rounded, size: 20, color: Color(0xFF9A4A06)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Color(0xFF9A4A06)),
          ),
        ),
      ],
    ),
  );
}
