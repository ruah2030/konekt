import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../data/auth_repository.dart';
import 'auth_controller.dart';

class OtpState {
  const OtpState({this.code = '', this.busy = false, this.error});
  final String code;
  final bool busy;
  final ApiFailure? error;
}

final otpControllerProvider = NotifierProvider.autoDispose<OtpController, OtpState>(OtpController.new);

/// Saisie de l'OTP de connexion : validation, renvoi (max 3 par heure).
class OtpController extends Notifier<OtpState> {
  static const expiredMessage = 'Ce code a expiré. Demandez-en un nouveau.';

  @override
  OtpState build() => const OtpState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  void setCode(String code) {
    if (state.busy) return;
    state = OtpState(code: code);
  }

  /// Valide l'OTP. En cas de succès, l'état d'auth passe à « connecté » (le routeur redirige).
  Future<bool> submit(String code) async {
    final challenge = ref.read(loginChallengeProvider);
    if (state.busy || challenge == null) return false;
    if (DateTime.now().isAfter(challenge.expiresAt)) {
      state = OtpState(error: ApiFailure.local(ErrorCodes.unauthenticated, expiredMessage));
      return false;
    }
    state = OtpState(code: code, busy: true);
    try {
      final hasPin = await _repo.verifyOtp(challengeId: challenge.challengeId, code: code);
      ref.read(authControllerProvider.notifier).signedIn(hasPin: hasPin);
      return true;
    } catch (e) {
      if (ref.mounted) state = OtpState(error: ApiFailure.from(e));
      return false;
    }
  }

  /// Renvoie un nouveau code. Renvoie `true` si un code a été envoyé.
  Future<bool> resend() async {
    final challenge = ref.read(loginChallengeProvider);
    if (state.busy || challenge == null || challenge.sendsLeft <= 0) return false;
    state = const OtpState(busy: true);
    try {
      final next = await _repo.resendOtp(challenge.challengeId);
      ref.read(loginChallengeProvider.notifier).set(next);
      if (ref.mounted) state = const OtpState();
      return true;
    } catch (e) {
      if (ref.mounted) state = OtpState(error: ApiFailure.from(e));
      return false;
    }
  }
}
