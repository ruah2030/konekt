import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/operation.dart';
import '../../../../core/domain/promotion.dart';
import '../../../../core/domain/service_type.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/utils/relative_date.dart';
import '../../../../design_system/design_system.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../promotions/presentation/promo_slot.dart';
import '../../data/payment_repository.dart';
import '../providers/payment_flow.dart';

/// Opération affichée sur le reçu (`GET /cards/operations/:id`, qui couvre aussi le catalogue).
final receiptOperationProvider = FutureProvider.autoDispose.family<Operation, String>(
  (ref, id) => ref
      .watch(paymentRepositoryProvider)
      .operation(id, sessionCardCustomerId: ref.watch(cardSessionProvider)?.cardCustomerId),
);

/// Reçu d'une opération (fin de paiement ou depuis l'historique).
class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({required this.operationId, this.fromHistory = false, super.key});
  final String operationId;
  final bool fromHistory;

  void _close(BuildContext context, WidgetRef ref) {
    if (fromHistory) {
      context.canPop() ? context.pop() : context.go(Routes.history);
    } else {
      ref.read(paymentFlowProvider.notifier).reset();
      context.go(Routes.home);
    }
  }

  /// Informations connues seulement de l'app pour le paiement qui vient d'aboutir.
  List<ReceiptExtra> _extras(WidgetRef ref, Operation op) {
    final flow = ref.read(paymentFlowProvider);
    if (fromHistory || flow.operationId != op.id || !op.status.isSuccess) return const [];
    final request = flow.request;
    final input = request?.input ?? const {};
    return [
      if (request?.accessCode != null)
        ReceiptExtra(
          label: 'Code d’accès à communiquer',
          value: request!.accessCode!,
          note: 'Le code de retrait a été envoyé au bénéficiaire, sans ce code d’accès : transmettez-le-lui vous-même.',
        ),
      if (op.service == ServiceType.cash && request?.accessCode == null)
        ReceiptExtra(
          label: 'Code de retrait',
          value: 'Envoyé au bénéficiaire',
          note: 'Le code et le code d’accès ont été envoyés au ${input['beneficiaryContact']}.',
        ),
      if (op.service == ServiceType.elec)
        ReceiptExtra(
          label: 'Jeton de recharge',
          value: 'Envoyé par ${input['recipientChannel'] == 'email' ? 'e-mail' : 'WhatsApp'}',
          note: 'Destinataire : ${input['recipientContact']}.',
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receiptOperationProvider(operationId));
    final flow = ref.watch(paymentFlowProvider);
    final providerRef = flow.operationId == operationId ? flow.execution?.providerReference : null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('receipt-back'),
          tooltip: 'Retour',
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () => _close(context, ref),
        ),
        title: const Text('Reçu'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: ErrorView(error: e, onRetry: () => ref.invalidate(receiptOperationProvider(operationId))),
        ),
        data: (op) => _ReceiptBody(op: op, extras: _extras(ref, op), providerReference: providerRef),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            key: const Key('receipt-done'),
            onPressed: () => _close(context, ref),
            child: const Text('Terminé'),
          ),
        ),
      ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.op, required this.extras, this.providerReference});
  final Operation op;
  final List<ReceiptExtra> extras;
  final String? providerReference;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = op.status;
    final (String pill, Color dot, Color ring, IconData icon, Color pillColor) = s.isSuccess
        ? (
            op.isCredit ? 'Recharge réussie' : 'Paiement réussi',
            KColors.success,
            KColors.successContainer,
            Symbols.check_rounded,
            KColors.successDark,
          )
        : s.isFailure
        ? (
            switch (s) {
              OperationStatus.cancelled => 'Paiement annulé',
              OperationStatus.expired => 'Paiement expiré',
              _ => 'Paiement échoué',
            },
            KColors.error,
            KColors.errorContainer,
            Symbols.close_rounded,
            KColors.onErrorContainer,
          )
        : !s.isFinal
        ? (
            'Paiement en cours',
            KColors.warning,
            const Color(0xFFFFF0E6),
            Symbols.more_horiz_rounded,
            KColors.warningDark,
          )
        : (
            s == OperationStatus.refunded ? 'Paiement remboursé' : 'Paiement contre-passé',
            KColors.info,
            KColors.infoContainer,
            Symbols.undo_rounded,
            KColors.info,
          );
    final topup = op.service == ServiceType.topup;
    final reference = op.reference ?? op.id;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                child: Icon(icon, size: 30, weight: 700, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            pill,
            key: const Key('receipt-status'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pillColor),
          ),
          const SizedBox(height: 6),
          Center(child: StatusPill.operation(s, key: const Key('receipt-pill'))),
          const SizedBox(height: 10),
          Text(
            formatSignedFcfa(op.signedDisplayAmount),
            key: const Key('receipt-amount'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: KColors.primary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${op.title} · ${relativeDate(op.createdAt)}',
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: KColors.onSurfaceVariant, fontWeight: FontWeight.w500),
          ),
          for (final x in extras) ...[const SizedBox(height: 18), _ExtraCard(extra: x)],
          const SizedBox(height: 18),
          InfoRowsCard([
            if (op.reason != null) InfoRow('Motif', op.reason!, key: const Key('receipt-reason')),
            InfoRow(
              topup ? 'Prélevé sur le portefeuille' : (s.isSuccess ? 'Vous avez payé' : 'Montant débité prévu'),
              formatFcfa(op.amountDebited),
            ),
            InfoRow('Frais', op.fee > 0 ? formatFcfa(op.fee) : 'Aucun'),
            InfoRow(topup ? 'Crédité sur la carte' : 'Le bénéficiaire reçoit', formatFcfa(op.amountCredited)),
            if (op.counterparty != null && op.counterparty!.isNotEmpty)
              InfoRow(topup ? 'Depuis' : 'Bénéficiaire', op.counterparty!, key: const Key('receipt-counterparty')),
            if (providerReference != null) InfoRow('Réf. partenaire', providerReference!),
          ]),
          const SizedBox(height: 12),
          _ReferenceRow(reference: reference),
          const SizedBox(height: 18),
          const PromoSlot(placement: PromoPlacement.receipt),
        ],
      ),
    );
  }
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({required this.reference});
  final String reference;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Réf. $reference',
            key: const Key('receipt-reference'),
            style: t.bodySmall?.copyWith(color: KColors.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton.icon(
          key: const Key('receipt-copy-ref'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: reference));
            if (context.mounted) showToast(context, 'Référence copiée.');
          },
          icon: const Icon(Symbols.content_copy_rounded, size: 18),
          label: const Text('Copier'),
        ),
      ],
    );
  }
}

class _ExtraCard extends StatelessWidget {
  const _ExtraCard({required this.extra});
  final ReceiptExtra extra;

  @override
  Widget build(BuildContext context) {
    const sub = Color(0xFFB8BCE8);
    final copyable = RegExp(r'^[\d\s]+$').hasMatch(extra.value);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
      decoration: BoxDecoration(color: KColors.primary, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  extra.label,
                  style: const TextStyle(fontSize: 13, color: sub, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  extra.value,
                  style: TextStyle(
                    fontSize: copyable ? 22 : 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: copyable ? 1.3 : 0,
                    color: KColors.navIndicator,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (extra.note != null) ...[
                  const SizedBox(height: 8),
                  Text(extra.note!, style: const TextStyle(fontSize: 12, color: sub)),
                ],
              ],
            ),
          ),
          if (copyable)
            IconButton(
              key: const Key('receipt-copy'),
              tooltip: 'Copier',
              icon: const Icon(Symbols.content_copy_rounded, color: KColors.onPrimary),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: extra.value.replaceAll(' ', '')));
                if (context.mounted) showToast(context, 'Code copié.');
              },
            ),
        ],
      ),
    );
  }
}
