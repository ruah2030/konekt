import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../core/providers/ticker.dart';
import '../../data/card_repository.dart';
import '../../domain/sensitive_card_data.dart';

/// État de l'écran « Données de ma carte ».
sealed class SecureDisplayState {
  const SecureDisplayState();
}

class SecureDisplayLoading extends SecureDisplayState {
  const SecureDisplayLoading();
}

class SecureDisplayShown extends SecureDisplayState {
  const SecureDisplayShown(this.data);
  final SensitiveCardData data;
}

class SecureDisplayExpired extends SecureDisplayState {
  const SecureDisplayExpired();
}

class SecureDisplayError extends SecureDisplayState {
  const SecureDisplayError(this.failure);
  final ApiFailure failure;
}

/// Ouvre l'affichage sécurisé, puis masque les données à l'expiration (60 s).
/// `autoDispose` : les données sensibles disparaissent dès que l'écran est quitté.
final secureDisplayProvider = NotifierProvider.autoDispose<SecureDisplayController, SecureDisplayState>(
  SecureDisplayController.new,
);

class SecureDisplayController extends Notifier<SecureDisplayState> {
  int _generation = 0;

  @override
  SecureDisplayState build() {
    ref
      ..listen<DateTime>(nowProvider, (_, now) => _checkExpiry(now))
      ..onDispose(() => _generation++);
    Future.microtask(open);
    return const SecureDisplayLoading();
  }

  Future<void> open() async {
    final gen = ++_generation;
    state = const SecureDisplayLoading();
    try {
      final data = await ref.read(cardRepositoryProvider).sensitiveDisplay();
      if (gen != _generation) return;
      state = SecureDisplayShown(data);
      _checkExpiry(ref.read(nowProvider));
    } catch (e) {
      if (gen != _generation) return;
      state = SecureDisplayError(ApiFailure.from(e));
    }
  }

  void _checkExpiry(DateTime now) {
    final s = state;
    if (s is SecureDisplayShown && !now.isBefore(s.data.expiresAt)) expire();
  }

  /// Efface les données sensibles de l'état.
  void expire() => state = const SecureDisplayExpired();
}
