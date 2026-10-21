import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../core/utils/validators.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_models.dart';
import 'auth_controller.dart';

class LoginState {
  const LoginState({this.channels, this.channel, this.busy = false, this.error, this.cardIdError, this.last4Error});

  /// Canaux de réception du code (`GET /auth/customer/channels`) ; null pendant le chargement.
  final ChannelAvailability? channels;

  /// Canal choisi (présélection : `defaultChannel`).
  final OtpChannel? channel;
  final bool busy;

  /// Erreur générale (sous le formulaire).
  final ApiFailure? error;

  /// Erreurs par champ (validation locale ou `VALIDATION_FAILED`).
  final String? cardIdError;
  final String? last4Error;

  LoginState copyWith({
    ChannelAvailability? channels,
    OtpChannel? channel,
    bool? busy,
    ApiFailure? error,
    String? cardIdError,
    String? last4Error,
    bool clearErrors = false,
  }) => LoginState(
    channels: channels ?? this.channels,
    channel: channel ?? this.channel,
    busy: busy ?? this.busy,
    error: clearErrors ? null : (error ?? this.error),
    cardIdError: clearErrors ? null : (cardIdError ?? this.cardIdError),
    last4Error: clearErrors ? null : (last4Error ?? this.last4Error),
  );
}

final loginControllerProvider = NotifierProvider.autoDispose<LoginController, LoginState>(LoginController.new);

/// Écran « Ma carte » (guide §2.2-2.3) : canaux disponibles, puis `login/init`.
class LoginController extends Notifier<LoginState> {
  static const letterOMessage =
      'Chiffres uniquement : vérifiez qu’aucune lettre « O » n’a été saisie à la place du zéro.';
  static const cardIdMessage = "L'identifiant de carte compte 6 à 20 chiffres.";
  static const last4Message = 'Quatre chiffres attendus.';
  static const invalidCredentialsMessage = 'Identifiant ou chiffres incorrects.';
  static const tooManyCallsMessage = 'Patientez une minute.';

  @override
  LoginState build() {
    Future.microtask(_loadChannels);
    return const LoginState();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _loadChannels() async {
    final channels = await _repo.channels();
    if (!ref.mounted) return;
    final preferred = channels.defaultChannel;
    final channel = preferred != null && channels.isAvailable(preferred)
        ? preferred
        : OtpChannel.values.where(channels.isAvailable).firstOrNull;
    state = state.copyWith(channels: channels, channel: channel);
  }

  void selectChannel(OtpChannel c) {
    if (state.busy || !(state.channels?.isAvailable(c) ?? false)) return;
    state = state.copyWith(channel: c);
  }

  void clearErrors() {
    if (state.error != null || state.cardIdError != null || state.last4Error != null) {
      state = state.copyWith(clearErrors: true);
    }
  }

  /// Validation locale puis `POST /auth/customer/login/init`. En cas de succès, le défi est
  /// enregistré dans [loginChallengeProvider] et renvoyé ; `null` en cas d'erreur.
  Future<LoginChallenge?> submit({required String cardId, required String last4}) async {
    if (state.busy) return null;
    final raw = Validators.digitsOnly(cardId);
    final cardIdError = Validators.containsLetterO(raw)
        ? letterOMessage
        : !Validators.isCardId(raw)
        ? cardIdMessage
        : null;
    final last4Error = Validators.isLast4(last4) ? null : last4Message;
    if (cardIdError != null || last4Error != null) {
      state = state.copyWith(clearErrors: true);
      state = state.copyWith(cardIdError: cardIdError, last4Error: last4Error);
      return null;
    }
    state = state.copyWith(busy: true, clearErrors: true);
    try {
      final c = await _repo.loginInit(cardId: raw, last4: last4, channel: state.channel);
      if (!ref.mounted) return null;
      ref.read(loginChallengeProvider.notifier).set(c);
      state = state.copyWith(busy: false);
      return c;
    } catch (e) {
      if (ref.mounted) _fail(ApiFailure.from(e));
      return null;
    }
  }

  void _fail(ApiFailure f) {
    final base = state.copyWith(busy: false, clearErrors: true);
    if (f.code == ErrorCodes.validationFailed) {
      final cardId = f.fieldErrors('cardCustomerId');
      final last4 = f.fieldErrors('last4Digits');
      if (cardId.isNotEmpty || last4.isNotEmpty) {
        state = base.copyWith(cardIdError: cardId.firstOrNull, last4Error: last4.firstOrNull);
        return;
      }
    }
    state = base.copyWith(error: loginFailure(f));
  }

  /// Messages imposés par le guide (§2.3) : 401 volontairement vague, 429 générique, sinon `message`.
  static ApiFailure loginFailure(ApiFailure f) => switch (f.statusCode) {
    401 => ApiFailure(code: f.code, message: invalidCredentialsMessage, ref: f.ref, statusCode: 401),
    429 => ApiFailure(code: f.code, message: tooManyCallsMessage, ref: f.ref, statusCode: 429),
    _ => f,
  };
}
