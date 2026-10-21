import 'package:flutter/material.dart';

import '../../core/domain/card.dart';
import '../../core/domain/operation.dart';
import '../theme/app_colors.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.color, required this.background, super.key});

  factory StatusPill.card(CardStatus s, {Key? key}) {
    final (fg, bg) = switch (s) {
      CardStatus.active => (KColors.successDark, KColors.successContainer),
      CardStatus.inactive => (KColors.onSecondaryContainer, KColors.secondaryContainer),
      CardStatus.preActive => (KColors.info, KColors.infoContainer),
      CardStatus.lostOrStolen || CardStatus.deactivated => (KColors.onErrorContainer, KColors.errorContainer),
    };
    return StatusPill(label: s.label, color: fg, background: bg, key: key);
  }

  factory StatusPill.operation(OperationStatus s, {Key? key}) {
    if (s.isSuccess) {
      return StatusPill(label: s.label, color: KColors.successDark, background: KColors.successContainer, key: key);
    }
    if (s.isFailure) {
      return StatusPill(label: s.label, color: KColors.onErrorContainer, background: KColors.errorContainer, key: key);
    }
    if (!s.isFinal) {
      return StatusPill(label: s.label, color: KColors.warningDark, background: KColors.warningContainer, key: key);
    }
    return StatusPill(label: s.label, color: KColors.info, background: KColors.infoContainer, key: key);
  }

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ],
    ),
  );
}
