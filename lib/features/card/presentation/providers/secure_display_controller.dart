import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../core/providers/ticker.dart';
import '../../../account/presentation/account_providers.dart';
import '../../data/card_repository.dart';
import '../../domain/card_models.dart';
import '../widgets/card_display_view.dart';

/// État de l'écran « Données de ma carte » (guide Partie 4 §14).
sealed class SecureDisplayState {
  const SecureDisplayState();
}

/// Rien n'est demandé tant que le porteur n'a pas tapé « Afficher » (chaque autorisation est décomptée).
class SecureDisplayIdle extends SecureDisplayState {
  const SecureDisplayIdle();
}

class SecureDisplayLoading extends SecureDisplayState {
  const SecureDisplayLoading();
}

class SecureDisplayShown extends SecureDisplayState {
  const SecureDisplayShown(this.authorization, this.deadline, this.generation);
  final DisplayAuthorization authorization;

  /// Échéance locale de l'affichage.
  final DateTime deadline;

  /// Numéro d'autorisation : chaque « Afficher » crée une vue neuve (jamais de rechargement).
  final int generation;
}

class SecureDisplayExpired extends SecureDisplayState {
  const SecureDisplayExpired();
}

class SecureDisplayError extends SecureDisplayState {
  const SecureDisplayError(this.failure);
  final ApiFailure failure;

  /// 403 = refus métier (plafond du jour, volume inhabituel, carte bloquée) : réessayer ne changerait rien.
  bool get canRetry => failure.code != ErrorCodes.forbidden && failure.code != ErrorCodes.requestRejected;
}

/// `autoDispose` : l'adresse disparaît dès que l'écran est quitté.
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
    return const SecureDisplayIdle();
  }

  /// Tap sur « Afficher » / « Afficher à nouveau » : nouvelle autorisation à chaque fois.
  Future<void> authorize() async {
    if (state is SecureDisplayLoading) return;
    final gen = ++_generation;
    state = const SecureDisplayLoading();
    try {
      final auth = await ref.read(cardRepositoryProvider).authorizeDisplay(requireCardId(ref));
      if (gen != _generation) return;
      state = SecureDisplayShown(auth, auth.deadlineFrom(ref.read(nowProvider)), gen);
      _checkExpiry(ref.read(nowProvider));
    } catch (e) {
      if (gen != _generation) return;
      state = SecureDisplayError(ApiFailure.from(e));
    }
  }

  void _checkExpiry(DateTime now) {
    final s = state;
    if (s is SecureDisplayShown && !now.isBefore(s.deadline)) expire();
  }

  /// Retire la vue (et donc détruit la WebView).
  void expire() {
    _generation++;
    state = const SecureDisplayExpired();
  }
}

/// Fabrique de la vue qui charge `displayUrl` (WebView en production). Remplaçable dans les tests,
/// où la WebView n'a pas d'implémentation de plateforme.
typedef CardDisplayViewBuilder = Widget Function(BuildContext context, Uri displayUrl);

final cardDisplayViewBuilderProvider = Provider<CardDisplayViewBuilder>(
  (ref) =>
      (context, url) => CardDisplayView(displayUrl: url),
);
