import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/session.dart';

/// Données sensibles : jetons et session porteur (Keychain iOS / Keystore Android).
/// Les jetons ne doivent jamais apparaître dans les journaux ni dans une URL.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  static const _sessionTokenKey = 'session_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _sessionKey = 'card_session';

  String? _sessionCache;
  CardSession? _cardSessionCache;

  /// Jeton de session (`Authorization: Bearer …`).
  Future<String?> get sessionToken async => _sessionCache ??= await _s.read(key: _sessionTokenKey);
  Future<String?> get refreshToken => _s.read(key: _refreshTokenKey);

  /// Remplace TOUJOURS les deux jetons ensemble (le refresh token est à usage unique).
  Future<void> saveTokens({required String session, required String refresh}) async {
    _sessionCache = session;
    await _s.write(key: _sessionTokenKey, value: session);
    await _s.write(key: _refreshTokenKey, value: refresh);
  }

  /// Carte de la session (identifiant émetteur, titulaire, `hasPin`…).
  Future<CardSession?> get cardSession async {
    if (_cardSessionCache != null) return _cardSessionCache;
    final raw = await _s.read(key: _sessionKey);
    if (raw == null) return null;
    return _cardSessionCache = CardSession.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  Future<void> saveCardSession(CardSession session) async {
    _cardSessionCache = session;
    await _s.write(key: _sessionKey, value: jsonEncode(session.toJson()));
  }

  /// Efface jetons et session (déconnexion, même si l'appel réseau a échoué).
  Future<void> clear() async {
    _sessionCache = null;
    _cardSessionCache = null;
    await _s.delete(key: _sessionTokenKey);
    await _s.delete(key: _refreshTokenKey);
    await _s.delete(key: _sessionKey);
  }
}

/// Stockage en mémoire, utilisé dans les tests.
class InMemorySecureStore extends SecureStore {
  InMemorySecureStore() : super(const FlutterSecureStorage());
  String? _st, _rt;
  CardSession? _cs;

  @override
  Future<String?> get sessionToken async => _st;
  @override
  Future<String?> get refreshToken async => _rt;
  @override
  Future<void> saveTokens({required String session, required String refresh}) async {
    _st = session;
    _rt = refresh;
  }

  @override
  Future<CardSession?> get cardSession async => _cs;
  @override
  Future<void> saveCardSession(CardSession session) async => _cs = session;
  @override
  Future<void> clear() async => _st = _rt = _cs = null;
}

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());
