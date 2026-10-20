import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/network/api_failure.dart';
import '../theme/app_colors.dart';

/// Erreur inline : message + « CODE · Réf. req_… » pour le support.
class ErrorBlock extends StatelessWidget {
  const ErrorBlock(this.failure, {super.key});
  final ApiFailure failure;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      key: const Key('error-block'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: KColors.errorContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.error_rounded, color: KColors.error, size: 20, fill: 1),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failure.message,
                  style: t.bodyMedium?.copyWith(color: KColors.onErrorContainer, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  [failure.code, if (failure.ref != null) 'Réf. ${failure.ref}'].join(' · '),
                  style: t.labelSmall?.copyWith(color: KColors.onErrorContainer.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
