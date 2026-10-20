import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// « Incident chez un opérateur : certains paiements peuvent être ralentis. »
class IncidentBanner extends StatelessWidget {
  const IncidentBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('incident-banner'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: KColors.warningContainer, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        const Icon(Symbols.warning_rounded, color: KColors.warning, size: 20, fill: 1),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: KColors.warningDark, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

/// Pastille de compte à rebours (« Prix garanti · 9:42 »).
class CountdownChip extends StatelessWidget {
  const CountdownChip({required this.label, this.expired = false, super.key});
  final String label;
  final bool expired;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: expired ? KColors.errorContainer : KColors.secondaryContainer,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Symbols.timer_rounded, size: 16, color: expired ? const Color(0xFF9B1C1C) : KColors.onSecondaryContainer),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: expired ? const Color(0xFF9B1C1C) : KColors.onSecondaryContainer,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

/// Mention de pied de page.
class PoweredBy extends StatelessWidget {
  const PoweredBy({this.text = 'POWERED BY BESTCASH CARDS BÉNIN', this.color = KColors.outline, super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: color),
  );
}
