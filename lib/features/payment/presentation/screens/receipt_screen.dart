import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/operation.dart';
import '../../../../core/domain/promotion.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/utils/relative_date.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/data/account_repository.dart';
import '../../../promotions/presentation/promo_slot.dart';

/// Opération affichée sur le reçu.
final receiptOperationProvider = FutureProvider.autoDispose.family<Operation, String>(
  (ref, id) => ref.watch(accountRepositoryProvider).operation(id),
);

/// Reçu d'une opération (fin de paiement ou depuis l'historique).
class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({required this.operationId, this.fromHistory = false, super.key});
  final String operationId;
  final bool fromHistory;

  void _close(BuildContext context) {
    if (fromHistory) {
      context.canPop() ? context.pop() : context.go(Routes.history);
    } else {
      context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receiptOperationProvider(operationId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('receipt-back'),
          tooltip: 'Retour',
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () => _close(context),
        ),
        title: const Text('Reçu'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: ErrorView(error: e, onRetry: () => ref.invalidate(receiptOperationProvider(operationId))),
        ),
        data: (op) => _ReceiptBody(op: op),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            key: const Key('receipt-done'),
            onPressed: () => _close(context),
            child: const Text('Terminé'),
          ),
        ),
      ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.op});
  final Operation op;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (pill, dot, ring, icon, pillColor) = switch (op.status) {
      OperationStatus.success => (
        'Paiement réussi',
        KColors.success,
        KColors.successContainer,
        Symbols.check_rounded,
        KColors.successDark,
      ),
      OperationStatus.failed => (
        'Paiement échoué',
        KColors.error,
        KColors.errorContainer,
        Symbols.close_rounded,
        KColors.onErrorContainer,
      ),
      OperationStatus.processing => (
        'En cours',
        KColors.warning,
        const Color(0xFFFFF0E6),
        Symbols.more_horiz_rounded,
        KColors.warningDark,
      ),
    };
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
          if (op.status == OperationStatus.success)
            for (final x in op.extra) ...[const SizedBox(height: 18), _ExtraCard(extra: x)],
          const SizedBox(height: 18),
          InfoRowsCard([
            if (op.reason != null) InfoRow('Motif', op.reason!),
            InfoRow('Montant', formatFcfa(op.amount)),
            InfoRow('Frais', op.fee > 0 ? formatFcfa(op.fee) : 'Aucun'),
            if (op.beneficiary != null) InfoRow(op.isCredit ? 'Depuis' : 'Bénéficiaire', op.beneficiary!),
            InfoRow('Réf.', op.id),
          ]),
          const SizedBox(height: 18),
          const PromoSlot(placement: PromoPlacement.receipt),
        ],
      ),
    );
  }
}

class _ExtraCard extends StatelessWidget {
  const _ExtraCard({required this.extra});
  final ReceiptExtra extra;

  @override
  Widget build(BuildContext context) {
    const sub = Color(0xFFB8BCE8);
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
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: KColors.navIndicator,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (extra.note != null) ...[
                  const SizedBox(height: 8),
                  Text(extra.note!, style: const TextStyle(fontSize: 12, color: sub)),
                ],
              ],
            ),
          ),
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
