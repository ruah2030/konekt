import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/network/api_failure.dart';
import '../theme/app_colors.dart';
import 'error_block.dart';

/// Message court (SnackBar) : « Nouveau code envoyé. », « Préférence enregistrée. »
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 2600)));
}

/// Dialogue de confirmation (suspendre, perte/vol, déconnexion…). Renvoie `true` si confirmé.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required IconData icon,
  Color color = KColors.primary,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 28),
      ),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: Text(body, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        FilledButton(
          key: const Key('confirm-dialog-ok'),
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
        TextButton(
          key: const Key('confirm-dialog-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Écran/zone d'erreur de chargement avec bouton « Réessayer ».
class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, required this.onRetry, super.key});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ErrorBlock(ApiFailure.from(error)),
        const SizedBox(height: 12),
        TextButton.icon(onPressed: onRetry, icon: const Icon(Symbols.refresh_rounded), label: const Text('Réessayer')),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.message, this.icon = Symbols.receipt_long_rounded, super.key});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
    child: Column(
      children: [
        Icon(icon, size: 40, color: KColors.outline),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: KColors.onSurfaceVariant),
        ),
      ],
    ),
  );
}
