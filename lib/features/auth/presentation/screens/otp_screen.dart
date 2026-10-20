import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/ticker.dart';
import '../../../../core/utils/countdown.dart';
import '../../../../design_system/design_system.dart';
import '../../../pin/presentation/widgets/code_entry_view.dart';
import '../../domain/auth_models.dart';
import '../providers/auth_controller.dart';
import '../providers/otp_controller.dart';

/// Saisie du code à usage unique reçu après la connexion par carte.
class OtpScreen extends ConsumerWidget {
  const OtpScreen({super.key});

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go(Routes.login);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenge = ref.watch(loginChallengeProvider);
    if (challenge == null) {
      // Aucun défi en cours (ex. redémarrage) : retour à la connexion, sauf si la session vient d'être ouverte.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && !ref.read(authControllerProvider).isAuthenticated) context.go(Routes.login);
      });
      return const Scaffold(backgroundColor: KColors.surface);
    }
    final s = ref.watch(otpControllerProvider);
    final ctrl = ref.read(otpControllerProvider.notifier);
    final now = ref.watch(nowProvider);
    final by = challenge.channel == OtpChannel.email ? 'e-mail' : 'SMS';
    final limitReached = challenge.sendsLeft <= 0;

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
                'Envoyé au ${challenge.maskedDestination} par $by. '
                'Expire dans ${mmss(remaining(challenge.expiresAt, now))}.',
            value: s.code,
            error: s.error,
            busy: s.busy,
            onBack: () => _back(context),
            onChanged: ctrl.setCode,
            onCompleted: ctrl.submit,
            link: CodeEntryLink(
              label: limitReached ? 'Limite de 3 codes par heure atteinte' : 'Renvoyer un code',
              enabled: !limitReached,
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
