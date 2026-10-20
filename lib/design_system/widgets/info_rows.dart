import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class InfoRow {
  const InfoRow(this.label, this.value, {this.emphasis = false, this.key});
  final String label;
  final String value;
  final bool emphasis;
  final Key? key;
}

/// Carte de lignes libellé / valeur (devis, reçu, infos carte).
class InfoRowsCard extends StatelessWidget {
  const InfoRowsCard(this.rows, {super.key});
  final List<InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              Container(
                key: rows[i].key,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: i == 0 ? null : const Border(top: BorderSide(color: KColors.divider)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(rows[i].label, style: t.bodyMedium?.copyWith(color: KColors.onSurfaceVariant)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Text(
                        rows[i].value,
                        textAlign: TextAlign.right,
                        style: t.bodyMedium?.copyWith(fontWeight: rows[i].emphasis ? FontWeight.w800 : FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
