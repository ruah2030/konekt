import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../account/presentation/account_providers.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_models.dart';

/// État d'authentification global. Le routeur l'écoute pour ses redirections.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  StreamSubscription<void>? _expiredSub;

  @override
  AuthState build() {
    _expiredSub = ref.watch(sessionExpiredProvider).stream.listen((_) => _clearSession());
    ref.onDispose(() => _expiredSub?.cancel());
    Future.microtask(_restore);
    return const AuthState.unknown();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _restore() async {
    final hasPin = await _repo.restore();
    state = hasPin == null ? const AuthState.unauthenticated() : AuthState(AuthStatus.authenticated, hasPin: hasPin);
  }

  /// Après validation de l'OTP.
  void signedIn({required bool hasPin}) {
    ref.read(loginChallengeProvider.notifier).clear();
    resetAccountState(ref);
    state = AuthState(AuthStatus.authenticated, hasPin: hasPin);
  }

  /// Après création du code secret.
  void pinCreated() => state = const AuthState(AuthStatus.authenticated, hasPin: true);

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

  /// Session terminée localement (déconnexion, révocation, refresh impossible).
  void sessionEnded() => _clearSession();

  void _clearSession() {
    ref.read(loginChallengeProvider.notifier).clear();
    resetAccountState(ref);
    state = const AuthState.unauthenticated();
  }
}

/// Défi OTP en cours (entre l'écran de connexion et l'écran de code).
final loginChallengeProvider = NotifierProvider<LoginChallengeNotifier, LoginChallenge?>(LoginChallengeNotifier.new);

class LoginChallengeNotifier extends Notifier<LoginChallenge?> {
  @override
  LoginChallenge? build() => null;
  void set(LoginChallenge c) => state = c;
  void clear() => state = null;
}
