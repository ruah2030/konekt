import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../core/utils/validators.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_models.dart';

class LoginState {
  const LoginState({this.channel = OtpChannel.sms, this.busy = false, this.error});
  final OtpChannel channel;
  final bool busy;
  final ApiFailure? error;

  LoginState copyWith({OtpChannel? channel, bool? busy, ApiFailure? error, bool clearError = false}) => LoginState(
    channel: channel ?? this.channel,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
  );
}

final loginControllerProvider = NotifierProvider.autoDispose<LoginController, LoginState>(LoginController.new);

class LoginController extends Notifier<LoginState> {
  /// Canal désactivé par configuration (maquette : WhatsApp indisponible).
  static const disabledChannels = {OtpChannel.whatsapp};

  static const letterOMessage =
      'Chiffres uniquement : vérifiez qu’aucune lettre « O » n’a été saisie à la place du zéro.';
  static const cardIdMessage = "L'identifiant de carte compte 6 à 20 chiffres.";
  static const last4Message = 'Quatre chiffres attendus.';

  @override
  LoginState build() => const LoginState();

  void selectChannel(OtpChannel c) {
    if (disabledChannels.contains(c)) return;
    state = state.copyWith(channel: c);
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  /// Validation locale puis `POST /v1/auth/login`. Renvoie le défi OTP, ou `null` en cas d'erreur.
  Future<LoginChallenge?> submit({required String cardId, required String last4}) async {
    if (state.busy) return null;
    final raw = Validators.digitsOnly(cardId);
    final local = Validators.containsLetterO(raw)
        ? ApiFailure.local(ErrorCodes.requestRejected, letterOMessage)
        : !Validators.isCardId(raw)
        ? ApiFailure.local(ErrorCodes.validationFailed, cardIdMessage)
        : !Validators.isLast4(last4)
        ? ApiFailure.local(ErrorCodes.validationFailed, last4Message)
        : null;
    if (local != null) {
      state = state.copyWith(error: local);
      return null;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      final c = await ref.read(authRepositoryProvider).login(cardId: raw, last4: last4, channel: state.channel);
      if (ref.mounted) state = state.copyWith(busy: false);
      return c;
    } catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: ApiFailure.from(e));
      return null;
    }
  }
}
