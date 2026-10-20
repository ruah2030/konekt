import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Données sensibles : tokens et identifiant d'appareil (Keychain / Keystore).
class SecureStore {
  SecureStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  static const _access = 'access_token';
  static const _refresh = 'refresh_token';
  static const _device = 'device_id';

  String? _accessCache;

  Future<String?> get accessToken async => _accessCache ??= await _s.read(key: _access);
  Future<String?> get refreshToken => _s.read(key: _refresh);

  Future<void> saveTokens({required String access, required String refresh}) async {
    _accessCache = access;
    await _s.write(key: _access, value: access);
    await _s.write(key: _refresh, value: refresh);
  }

  Future<void> clearTokens() async {
    _accessCache = null;
    await _s.delete(key: _access);
    await _s.delete(key: _refresh);
  }

  Future<String> deviceId() async {
    final existing = await _s.read(key: _device);
    if (existing != null) return existing;
    final id = const Uuid().v4();
    await _s.write(key: _device, value: id);
    return id;
  }
}

/// Stockage en mémoire, utilisé dans les tests.
class InMemorySecureStore extends SecureStore {
  InMemorySecureStore() : super(const FlutterSecureStorage());
  String? _a, _r;
  final String _d = const Uuid().v4();

  @override
  Future<String?> get accessToken async => _a;
  @override
  Future<String?> get refreshToken async => _r;
  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    _a = access;
    _r = refresh;
  }

  @override
  Future<void> clearTokens() async => _a = _r = null;
  @override
  Future<String> deviceId() async => _d;
}

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());
