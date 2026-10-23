import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/session.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_store.dart';
import '../../../account/presentation/account_providers.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_models.dart';

/// État d'authentification global. Le routeur l'écoute pour ses redirections.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Carte de la session courante (null si déconnecté).
final cardSessionProvider = Provider<CardSession?>((ref) => ref.watch(authControllerProvider).session);

class AuthController extends Notifier<AuthState> {
  StreamSubscription<void>? _expiredSub;

  @override
  AuthState build() {
    _expiredSub = ref.watch(sessionExpiredProvider).stream.listen((_) {
      if (state.status != AuthStatus.unauthenticated) _clearSession();
    });
    ref.onDispose(() => _expiredSub?.cancel());
    Future.microtask(_restore);
    return const AuthState.unknown();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Restauration au démarrage. Ne doit JAMAIS laisser l'état à `unknown` : le splash l'attend.
  /// Stockage sécurisé illisible (réinstallation, clés changées…), erreur ou délai dépassé →
  /// session effacée et retour à l'écran de connexion.
  Future<void> _restore() async {
    CardSession? session;
    try {
      session = await _repo.restore().timeout(restoreTimeout);
    } catch (_) {
      session = null;
      try {
        await ref.read(secureStoreProvider).clear();
      } catch (_) {}
    }
    if (!ref.mounted || state.status != AuthStatus.unknown) return;
    state = session == null ? const AuthState.unauthenticated() : AuthState.authenticated(session);
  }

  static const restoreTimeout = Duration(seconds: 10);

  /// Après `login/confirm`.
  void signedIn(CardSession session) {
    ref.read(loginChallengeProvider.notifier).clear();
    resetAccountState(ref);
    state = AuthState.authenticated(session);
  }

  /// Après création du code secret (`POST /auth/customer/pin`).
  Future<void> pinCreated() async {
    final s = state.session;
    if (s == null) return;
    await _repo.markPinCreated();
    state = AuthState.authenticated(s.copyWith(hasPin: true));
  }

  Future<void> logout() async {
    try {
      await _repo.logout();
    } finally {
      _clearSession();
    }
  }

  /// Renvoie le nombre de sessions fermées.
  Future<int> logoutAll() async {
    try {
      return await _repo.logoutAll();
    } finally {
      _clearSession();
    }
  }

  /// Session terminée localement (appareil courant déconnecté, révocation…).
  void sessionEnded() => _clearSession();

  void _clearSession() {
    // Les jetons locaux sont toujours effacés : un `restore()` ultérieur ne doit pas rouvrir la session.
    unawaited(ref.read(secureStoreProvider).clear());
    ref.read(loginChallengeProvider.notifier).clear();
    resetAccountState(ref);
    state = const AuthState.unauthenticated();
  }
}

/// Code de connexion en cours (entre l'écran carte et l'écran code).
final loginChallengeProvider = NotifierProvider<LoginChallengeNotifier, LoginChallenge?>(LoginChallengeNotifier.new);

class LoginChallengeNotifier extends Notifier<LoginChallenge?> {
  @override
  LoginChallenge? build() => null;
  void set(LoginChallenge c) => state = c;
  void clear() => state = null;
}
