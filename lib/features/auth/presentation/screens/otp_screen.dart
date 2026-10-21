import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/ticker.dart';
import '../../../../core/utils/countdown.dart';
import '../../../../design_system/design_system.dart';
import '../../../pin/presentation/widgets/code_entry_view.dart';
import '../providers/auth_controller.dart';
import '../providers/otp_controller.dart';

/// Saisie du code reçu après `login/init` (guide §2.4).
class OtpScreen extends ConsumerWidget {
  const OtpScreen({super.key});

  static const supportPhone = '+22921000000';
  static const supportMessage = 'Support Konekt : +229 21 00 00 00 (lun.–sam., 8h–20h)';

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go(Routes.login);

  /// Affiche le numéro du support et propose l'appel (si une application téléphone est disponible).
  static Future<void> contactSupport(BuildContext context) async {
    showToast(context, supportMessage);
    try {
      await launchUrl(Uri(scheme: 'tel', path: supportPhone));
    } catch (_) {
      // Pas d'application téléphone (tablette, web, tests) : le numéro reste affiché.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenge = ref.watch(loginChallengeProvider);
    if (challenge == null) {
      // Aucun code en cours (ex. redémarrage) : retour à la connexion, sauf si la session vient d'être ouverte.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && !ref.read(authControllerProvider).isAuthenticated) context.go(Routes.login);
      });
      return const Scaffold(backgroundColor: KColors.surface);
    }
    final s = ref.watch(otpControllerProvider);
    final ctrl = ref.read(otpControllerProvider.notifier);
    final now = ref.watch(nowProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back(context);
      },
      child: Scaffold(
        backgroundColor: KColors.surface,
        body: SafeArea(
          child: CodeEntryView(
            title: 'Saisissez le code reçu',
            subtitle:
                'Envoyé au ${challenge.destinationLabel}. '
                'Expire dans ${mmss(remaining(challenge.expiresAt, now))}',
            value: s.code,
            error: s.error,
            busy: s.busy,
            onBack: () => _back(context),
            onChanged: ctrl.setCode,
            onCompleted: ctrl.submit,
            link: s.contactSupport
                ? CodeEntryLink(label: 'Contacter le support', onTap: () => contactSupport(context))
                : CodeEntryLink(
                    label: 'Renvoyer un code',
                    onTap: () async {
                      if (await ctrl.resend() && context.mounted) showToast(context, 'Nouveau code envoyé.');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
