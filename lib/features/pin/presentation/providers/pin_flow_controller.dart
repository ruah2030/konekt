import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../core/utils/validators.dart';
import '../../data/pin_repository.dart';
import '../../domain/pin_flow.dart';

/// Étapes du parcours de code secret.
sealed class PinStep {
  const PinStep();
}

/// Code de vérification reçu par SMS et e-mail (setup, reset). Saisi en clair.
final class PinVerifyStep extends PinStep {
  const PinVerifyStep();
}

/// Code secret actuel (change).
final class PinOldStep extends PinStep {
  const PinOldStep();
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

/// Parcours terminé avec succès.
final class PinDoneStep extends PinStep {
  const PinDoneStep();
}

class PinFlowState {
  const PinFlowState({required this.flow, required this.step, this.code = '', this.busy = false, this.error});

  final PinFlow flow;
  final PinStep step;

  /// Saisie en cours (0 à 6 chiffres).
  final String code;
  final bool busy;
  final ApiFailure? error;

  bool get isDone => step is PinDoneStep;

  /// Les PIN sont masqués (●) ; le code de vérification est affiché en clair.
  bool get obscure => step is! PinVerifyStep;

  PinFlowState copyWith({PinStep? step, String? code, bool? busy, ApiFailure? error, bool clearError = false}) =>
      PinFlowState(
        flow: flow,
        step: step ?? this.step,
        code: code ?? this.code,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

final pinFlowControllerProvider = NotifierProvider.autoDispose.family<PinFlowController, PinFlowState, PinFlow>(
  PinFlowController.new,
);

/// Machine à états : setup/reset = vérification → nouveau → confirmation ; change = actuel → nouveau → confirmation.
class PinFlowController extends Notifier<PinFlowState> {
  PinFlowController(this.flow);
  final PinFlow flow;

  static const weakPinMessage = 'Code trop simple : évitez les chiffres identiques et les suites.';
  static const mismatchMessage = 'Les deux codes ne correspondent pas. Recommencez.';
  static const sameAsOldMessage = "Le nouveau code doit être différent de l'ancien.";

  String? _verificationToken;
  String? _currentPin;

  PinRepository get _repo => ref.read(pinRepositoryProvider);

  @override
  PinFlowState build() {
    if (flow == PinFlow.change) return PinFlowState(flow: flow, step: const PinOldStep());
    Future.microtask(sendVerificationCode);
    return PinFlowState(flow: flow, step: const PinVerifyStep());
  }

  /// (Ré)envoie le code de vérification par SMS et e-mail.
  Future<void> sendVerificationCode() async {
    try {
      await _repo.requestVerification();
    } catch (e) {
      if (ref.mounted) state = state.copyWith(error: ApiFailure.from(e));
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
      case PinVerifyStep():
        await _call(() async {
          _verificationToken = await _repo.confirmVerification(value);
          _go(const PinNewStep());
        });
      case PinOldStep():
        await _call(() async {
          await _repo.check(value);
          _currentPin = value;
          _go(const PinNewStep());
        });
      case PinNewStep():
        if (Validators.isWeakPin(value)) {
          return _fail(ApiFailure.local(ErrorCodes.pinTooWeak, weakPinMessage));
        }
        if (flow == PinFlow.change && value == _currentPin) {
          return _fail(ApiFailure.local(ErrorCodes.requestRejected, sameAsOldMessage));
        }
        _go(PinConfirmStep(value));
      case PinConfirmStep(:final firstEntry):
        if (value != firstEntry) {
          return _go(const PinNewStep(), error: ApiFailure.local(ErrorCodes.validationFailed, mismatchMessage));
        }
        await _call(() async {
          switch (flow) {
            case PinFlow.setup:
              await _repo.create(verificationToken: _verificationToken ?? '', pin: value);
            case PinFlow.reset:
              await _repo.reset(verificationToken: _verificationToken ?? '', pin: value);
            case PinFlow.change:
              await _repo.change(currentPin: _currentPin ?? '', newPin: value);
          }
          _verificationToken = null;
          _currentPin = null;
          _go(const PinDoneStep());
        }, onError: (f) => _go(const PinNewStep(), error: f));
      case PinDoneStep():
        return;
    }
  }

  /// Retour arrière interne : `pinConfirm → pinNew`. Renvoie `false` si l'écran doit être quitté.
  bool back() {
    if (state.busy) return true;
    if (state.step is PinConfirmStep) {
      _go(const PinNewStep());
      return true;
    }
    return false;
  }

  Future<void> _call(Future<void> Function() body, {void Function(ApiFailure)? onError}) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await body();
    } catch (e) {
      if (!ref.mounted) return;
      final f = ApiFailure.from(e);
      state = state.copyWith(busy: false);
      onError != null ? onError(f) : _fail(f);
    }
  }

  void _go(PinStep step, {ApiFailure? error}) {
    if (!ref.mounted) return;
    state = PinFlowState(flow: flow, step: step, error: error);
  }

  void _fail(ApiFailure f) => state = state.copyWith(code: '', busy: false, error: f);
}
