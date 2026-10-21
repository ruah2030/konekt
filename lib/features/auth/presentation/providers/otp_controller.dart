import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../data/auth_repository.dart';
import 'auth_controller.dart';
import 'login_controller.dart';

class OtpState {
  const OtpState({this.code = '', this.busy = false, this.error, this.contactSupport = false});
  final String code;
  final bool busy;
  final ApiFailure? error;

  /// 403 (carte perdue/volée, désactivée, région indisponible) : proposer « Contacter le support ».
  final bool contactSupport;
}

final otpControllerProvider = NotifierProvider.autoDispose<OtpController, OtpState>(OtpController.new);

/// Écran « Code reçu » (guide §2.4) : `login/confirm`, renvoi par un nouveau `login/init`.
class OtpController extends Notifier<OtpState> {
  static const expiredMessage = 'Ce code a expiré. Demandez-en un nouveau.';

  @override
  OtpState build() => const OtpState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  void setCode(String code) {
    if (state.busy) return;
    state = OtpState(code: code, contactSupport: state.contactSupport && code.isEmpty);
  }

  /// Valide le code. En cas de succès, la session est ouverte (le routeur redirige).
  Future<bool> submit(String code) async {
    final challenge = ref.read(loginChallengeProvider);
    if (state.busy || challenge == null) return false;
    if (DateTime.now().isAfter(challenge.expiresAt)) {
      state = OtpState(error: ApiFailure.local(ErrorCodes.unauthenticated, expiredMessage));
      return false;
    }
    state = OtpState(code: code, busy: true);
    try {
      final session = await _repo.loginConfirm(challenge, code);
      ref.read(authControllerProvider.notifier).signedIn(session);
      return true;
    } catch (e) {
      // 401 : code faux, expiré ou épuisé (message serveur) ; 403 : refus explicite + support.
      final f = ApiFailure.from(e);
      if (ref.mounted) state = OtpState(error: f, contactSupport: f.statusCode == 403);
      return false;
    }
  }

  /// « Renvoyer un code » : nouveau `login/init` avec les mêmes identifiants (3 codes / heure côté serveur).
  Future<bool> resend() async {
    final challenge = ref.read(loginChallengeProvider);
    if (state.busy || challenge == null) return false;
    state = const OtpState(busy: true);
    try {
      final next = await _repo.loginInit(
        cardId: challenge.cardCustomerId,
        last4: challenge.last4Digits,
        channel: challenge.channel,
      );
      if (!ref.mounted) return false;
      ref.read(loginChallengeProvider.notifier).set(next);
      state = const OtpState();
      return true;
    } catch (e) {
      if (ref.mounted) state = OtpState(error: LoginController.loginFailure(ApiFailure.from(e)));
      return false;
    }
  }
}
