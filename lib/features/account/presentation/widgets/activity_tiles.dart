import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/domain/operation.dart';
import '../../../../core/domain/transaction.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/utils/relative_date.dart';
import '../../../../design_system/theme/app_colors.dart';
import '../../../../design_system/widgets/tx_tile.dart';

IconData kindIcon(String kind) => switch (kind) {
  'send' || 'transfer' => Symbols.north_east_rounded,
  'payout' => Symbols.south_west_rounded,
  'plus' || 'topup' => Symbols.add_rounded,
  'phone' || 'airtime' => Symbols.smartphone_rounded,
  'data' => Symbols.wifi_rounded,
  'bolt' || 'elec' => Symbols.bolt_rounded,
  'tv' => Symbols.live_tv_rounded,
  'cash' => Symbols.payments_rounded,
  _ => Symbols.credit_card_rounded,
};

/// Mouvement du relevé (accueil, historique « Mouvements »).
class TransactionTile extends StatelessWidget {
  const TransactionTile(this.tx, {this.showDivider = false, super.key});
  final CardTransaction tx;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tint = tx.isCredit ? (bg: KColors.successContainer, fg: KColors.success) : kindTint(tx.kind);
    return TxTile(
      key: Key('tx-${tx.id}'),
      icon: kindIcon(tx.kind),
      tint: tint.bg,
      iconColor: tint.fg,
      title: tx.description,
      subtitle: relativeDate(tx.createdAt),
      amount: formatSignedFcfa(tx.amount),
      amountColor: tx.isCredit ? KColors.success : KColors.primary,
      trailingSub: tx.balanceAfter == null ? null : 'Solde ${formatNumber(tx.balanceAfter!)}',
      showDivider: showDivider,
    );
  }
}

/// Opération Konekt avec statut (historique « Mes opérations »).
class OperationTile extends StatelessWidget {
  const OperationTile(this.op, {this.onTap, this.showDivider = false, super.key});
  final Operation op;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final failed = op.status.isFailure;
    final tint = failed
        ? (bg: KColors.errorContainer, fg: KColors.error)
        : op.isCredit
        ? (bg: KColors.successContainer, fg: KColors.success)
        : kindTint(op.service?.id ?? 'card');
    final label = op.status.label;
    final color = op.status.isSuccess
        ? KColors.success
        : failed
        ? KColors.error
        : op.status.isFinal
        ? KColors.info
        : const Color(0xFFEA580C);
    return TxTile(
      key: Key('op-${op.id}'),
      icon: kindIcon(op.service?.id ?? 'card'),
      tint: tint.bg,
      iconColor: tint.fg,
      title: op.title,
      subtitle: [relativeDate(op.createdAt), ?op.counterparty].join(' · '),
      amount: formatSignedFcfa(op.signedDisplayAmount),
      amountColor: failed
          ? KColors.outline
          : op.isCredit
          ? KColors.success
          : KColors.primary,
      trailingSub: label,
      trailingSubColor: color,
      onTap: onTap,
      showDivider: showDivider,
    );
  }
}
