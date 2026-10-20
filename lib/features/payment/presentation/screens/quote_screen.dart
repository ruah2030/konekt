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
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/payment_models.dart';
import '../providers/payment_flow.dart';

/// Récapitulatif du devis : prix exact garanti 10 minutes.
class QuoteScreen extends ConsumerWidget {
  const QuoteScreen({super.key});

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go(Routes.home);

  void _confirm(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authControllerProvider);
    if (auth.isAuthenticated && !auth.hasPin) {
      showToast(context, "Créez d'abord votre code secret dans Profil.");
      return;
    }
    ref.read(paymentFlowProvider.notifier).clearPinError();
    context.push(Routes.payPin);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(paymentFlowProvider);
    final q = flow.quote;
    if (q == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Récapitulatif')),
        body: const EmptyState(message: 'Aucun devis en cours.'),
      );
    }
    final now = ref.watch(nowProvider);
    final expired = q.isExpired(now);
    final topup = q.service == ServiceType.topup;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('quote-back'),
          tooltip: 'Retour',
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () => _back(context),
        ),
        title: const Text('Récapitulatif'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: CountdownChip(
                key: const Key('quote-timer'),
                label: expired ? 'Prix expiré' : 'Prix garanti · ${mmss(remaining(q.expiresAt, now))}',
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
            _TotalCard(quote: q, topup: topup),
            const SizedBox(height: 16),
            InfoRowsCard([
              InfoRow(topup ? 'Crédité sur la carte' : 'Montant', formatFcfa(q.amount)),
              InfoRow('Frais', q.fee > 0 ? formatFcfa(q.fee) : 'Aucun'),
              if (q.beneficiary != null) InfoRow(topup ? 'Depuis' : 'Bénéficiaire', q.beneficiary!),
              if (q.service == ServiceType.payout) InfoRow('Le bénéficiaire reçoit', formatFcfa(q.amount)),
              InfoRow('Total', formatFcfa(q.total), emphasis: true),
            ]),
            for (final c in q.checks) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      c.passed ? Symbols.check_circle_rounded : Symbols.cancel_rounded,
                      fill: 1,
                      size: 22,
                      color: c.passed ? KColors.success : KColors.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: c.label,
                              style: const TextStyle(fontWeight: FontWeight.w700, color: KColors.primary),
                            ),
                            TextSpan(text: ' · ${c.detail}'),
                          ],
                        ),
                        style: t.bodyMedium?.copyWith(color: const Color(0xFF334155), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            for (final w in q.warnings) ...[const SizedBox(height: 16), _Warning(w)],
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
                  onPressed: () => _confirm(context, ref),
                  child: const Text('Confirmer le paiement'),
                ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const Key('quote-edit'),
                onPressed: () => _back(context),
                child: const Text('Modifier la demande'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.quote, required this.topup});
  final Quote quote;
  final bool topup;

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
                  topup ? 'Total prélevé sur votre Mobile Money' : 'Total débité de votre carte',
                  style: const TextStyle(fontSize: 13, color: sub, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  formatFcfa(quote.total),
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
