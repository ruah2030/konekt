import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Ligne de transaction/opération : icône teintée, libellé, date, montant signé.
class TxTile extends StatelessWidget {
  const TxTile({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
    this.trailingSub,
    this.trailingSubColor = KColors.outline,
    this.onTap,
    this.showDivider = false,
    super.key,
  });

  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;
  final String? trailingSub;
  final Color trailingSubColor;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: showDivider ? const Border(top: BorderSide(color: KColors.divider)) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.bodySmall?.copyWith(color: KColors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: amountColor),
                ),
                if (trailingSub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    trailingSub!,
                    style: t.bodySmall?.copyWith(color: trailingSubColor, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
