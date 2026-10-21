import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../data/pin_repository.dart';
import '../../domain/pin_flow.dart';
import '../../domain/pin_rules.dart';

/// Étapes du parcours de code secret.
sealed class PinStep {
  const PinStep();
}

/// Code de vérification reçu (setup, reset). Saisi en clair et gardé localement : il n'est envoyé
/// qu'avec le nouveau PIN.
final class PinCodeStep extends PinStep {
  const PinCodeStep();
}

/// Code secret actuel (change). Gardé localement, envoyé avec le nouveau PIN.
final class PinCurrentStep extends PinStep {
  const PinCurrentStep();
}

/// Nouveau code secret.
final class PinNewStep extends PinStep {
  const PinNewStep();
}

/// Confirmation du nouveau code. [firstEntry] ne quitte jamais la mémoire du notifier.
final class PinConfirmStep extends PinStep {
  const PinConfirmStep(this.firstEntry);
  final String firstEntry;
}

/// Parcours terminé. [alreadyDefined] : le serveur indique qu'un PIN existait déjà (`PIN_ALREADY_DEFINED`).
final class PinDoneStep extends PinStep {
  const PinDoneStep({this.alreadyDefined = false});
  final bool alreadyDefined;
}

class PinFlowState {
  const PinFlowState({
    required this.flow,
    required this.step,
    this.code = '',
    this.busy = false,
    this.error,
    this.sent,
  });

  final PinFlow flow;
  final PinStep step;

  /// Saisie en cours (0 à 6 chiffres).
  final String code;
  final bool busy;
  final ApiFailure? error;

  /// Dernier code de vérification envoyé (contacts masqués, validité).
  final PinCodeSent? sent;

  bool get isDone => step is PinDoneStep;

  /// Les PIN sont masqués (●) ; le code de vérification est affiché en clair.
  bool get obscure => step is! PinCodeStep;

  PinFlowState copyWith({
    PinStep? step,
    String? code,
    bool? busy,
    ApiFailure? error,
    bool clearError = false,
    PinCodeSent? sent,
  }) => PinFlowState(
    flow: flow,
    step: step ?? this.step,
    code: code ?? this.code,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    sent: sent ?? this.sent,
  );
}

final pinFlowControllerProvider = NotifierProvider.autoDispose.family<PinFlowController, PinFlowState, PinFlow>(
  PinFlowController.new,
);

/// Machine à états (guide §2.7) :
/// - setup / reset : `setup|reset/request` → code reçu → nouveau → confirmation → `POST pin` | `reset/confirm` ;
/// - change : actuel → nouveau → confirmation → `POST pin/change`.
class PinFlowController extends Notifier<PinFlowState> {
  PinFlowController(this.flow);
  final PinFlow flow;

  static const mismatchMessage = 'Les deux codes ne correspondent pas. Recommencez.';
  static const sameAsOldMessage = "Le nouveau code doit être différent de l'ancien.";
  static const newCodeSentSuffix = 'Un nouveau code vient de vous être envoyé.';

  /// Codes de vérification inutilisables : il faut en redemander un.
  static const _unusableCodes = {ErrorCodes.pinCodeExpired, ErrorCodes.pinCodeExhausted, ErrorCodes.pinCodeAlreadyUsed};

  String? _code;
  String? _currentPin;

  PinRepository get _repo => ref.read(pinRepositoryProvider);

  @override
  PinFlowState build() {
    if (flow == PinFlow.change) return PinFlowState(flow: flow, step: const PinCurrentStep());
    Future.microtask(requestCode);
    return PinFlowState(flow: flow, step: const PinCodeStep(), busy: true);
  }

  /// (Re)demande un code de vérification. [error] : message à conserver (ex. code expiré).
  Future<void> requestCode({ApiFailure? error}) async {
    if (!ref.mounted || state.isDone) return;
    _code = null;
    state = PinFlowState(flow: flow, step: const PinCodeStep(), busy: true, sent: state.sent);
    try {
      final sent = flow == PinFlow.reset ? await _repo.requestResetCode() : await _repo.requestSetupCode();
      if (!ref.mounted) return;
      state = PinFlowState(
        flow: flow,
        step: const PinCodeStep(),
        sent: sent,
        error: error == null
            ? null
            : ApiFailure(code: error.code, message: '${error.message} $newCodeSentSuffix', ref: error.ref),
      );
    } catch (e) {
      if (!ref.mounted) return;
      final f = ApiFailure.from(e);
      if (flow == PinFlow.setup && f.code == ErrorCodes.pinAlreadyDefined) {
        return _go(const PinDoneStep(alreadyDefined: true));
      }
      state = PinFlowState(flow: flow, step: const PinCodeStep(), sent: state.sent, error: f);
    }
  }

  void setCode(String code) {
    if (state.busy) return;
    state = state.copyWith(code: code, clearError: true);
  }

  /// Saisie complète (6 chiffres) : fait avancer la machine à états.
  Future<void> submit(String value) async {
    if (state.busy || state.isDone) return;
    switch (state.step) {
      case PinCodeStep():
        _code = value;
        _go(const PinNewStep());
      case PinCurrentStep():
        _currentPin = value;
        _go(const PinNewStep());
      case PinNewStep():
        final problem = PinRules.problem(value);
        if (problem != null) return _fail(ApiFailure.local(ErrorCodes.pinTooWeak, problem));
        if (flow == PinFlow.change && value == _currentPin) {
          return _fail(ApiFailure.local(ErrorCodes.requestRejected, sameAsOldMessage));
        }
        _go(PinConfirmStep(value));
      case PinConfirmStep(:final firstEntry):
        if (value != firstEntry) {
          return _go(const PinNewStep(), error: ApiFailure.local(ErrorCodes.validationFailed, mismatchMessage));
        }
        await _send(value);
      case PinDoneStep():
        return;
    }
  }

  Future<void> _send(String pin) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      switch (flow) {
        case PinFlow.setup:
          await _repo.create(pin: pin, code: _code ?? '');
        case PinFlow.reset:
          await _repo.confirmReset(code: _code ?? '', pin: pin);
        case PinFlow.change:
          await _repo.change(currentPin: _currentPin ?? '', pin: pin);
      }
      _code = null;
      _currentPin = null;
      _go(const PinDoneStep());
    } catch (e) {
      if (!ref.mounted) return;
      final f = ApiFailure.from(e);
      flow == PinFlow.change ? _onChangeError(f) : _onCodeFlowError(f);
    }
  }

  /// Erreurs de `POST pin` et `reset/confirm` (guide §2.7.1).
  void _onCodeFlowError(ApiFailure f) {
    final codeErrors = f.code == ErrorCodes.validationFailed ? f.fieldErrors('code') : const <String>[];
    switch (f.code) {
      case ErrorCodes.pinAlreadyDefined when flow == PinFlow.setup:
        _go(const PinDoneStep(alreadyDefined: true));
      case ErrorCodes.pinCodeInvalid:
        _code = null;
        final left = f.details['attemptsLeft'];
        final message = left is num ? 'Code incorrect, ${left.toInt()} essai(s) restant(s).' : f.message;
        _go(
          const PinCodeStep(),
          error: ApiFailure(code: f.code, message: message, ref: f.ref),
        );
      case final c when _unusableCodes.contains(c):
        unawaited(requestCode(error: f));
      case ErrorCodes.validationFailed when codeErrors.isNotEmpty:
        _code = null;
        _go(
          const PinCodeStep(),
          error: ApiFailure(code: f.code, message: codeErrors.first, ref: f.ref),
        );
      default:
        // PIN_TOO_WEAK, limites, réseau… : nouveau PIN à choisir, le code reçu reste valable.
        _go(const PinNewStep(), error: _withPinFieldError(f));
    }
  }

  /// Erreurs de `pin/change` (guide §2.7.2) : 403 = ancien PIN faux ou verrou, 400 = nouveau PIN refusé.
  void _onChangeError(ApiFailure f) {
    if (f.statusCode == 403) {
      _currentPin = null;
      _go(const PinCurrentStep(), error: f);
    } else {
      _go(const PinNewStep(), error: _withPinFieldError(f));
    }
  }

  ApiFailure _withPinFieldError(ApiFailure f) {
    final pinErrors = f.code == ErrorCodes.validationFailed ? f.fieldErrors('pin') : const <String>[];
    return pinErrors.isEmpty ? f : ApiFailure(code: f.code, message: pinErrors.first, ref: f.ref);
  }

  /// Retour arrière interne : `confirmation → nouveau`. Renvoie `false` si l'écran doit être quitté.
  bool back() {
    if (state.busy) return true;
    if (state.step is PinConfirmStep) {
      _go(const PinNewStep());
      return true;
    }
    return false;
  }

  void _go(PinStep step, {ApiFailure? error}) {
    if (!ref.mounted) return;
    state = PinFlowState(flow: flow, step: step, error: error, sent: state.sent);
  }

  void _fail(ApiFailure f) => state = state.copyWith(code: '', busy: false, error: f);
}
