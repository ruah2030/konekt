import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../storage/secure_store.dart';
import 'api_failure.dart';

/// En-têtes systématiques : X-Request-Id (affiché comme « Réf. » dans les erreurs),
/// identifiant d'appareil, version d'app et langue.
class RequestHeadersInterceptor extends Interceptor {
  RequestHeadersInterceptor(this._store, {required this.appVersion});
  final SecureStore _store;
  final String appVersion;
  static const _uuid = Uuid();

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    options.headers['X-Request-Id'] ??= 'req_${_uuid.v4().replaceAll('-', '').substring(0, 16).toUpperCase()}';
    options.headers['X-Device-Id'] = await _store.deviceId();
    options.headers['X-App-Version'] = appVersion;
    options.headers['Accept-Language'] = 'fr-BJ';
    handler.next(options);
  }
}

/// Ajoute le Bearer et rafraîchit le token sur 401 (une seule fois par requête).
/// Les requêtes concurrentes attendent le refresh en cours ([QueuedInterceptor]).
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.store,
    required this.refreshDio,
    required this.retryDio,
    required this.onSessionExpired,
  });

  final SecureStore store;
  final Dio refreshDio;
  final Dio retryDio;
  final void Function() onSessionExpired;

  /// Routes qui ne portent pas de Bearer.
  static const publicPaths = {
    '/v1/invitations/verify',
    '/v1/waitlist',
    '/v1/auth/login',
    '/v1/auth/otp/resend',
    '/v1/auth/otp/verify',
    '/v1/auth/refresh',
    '/v1/status',
  };

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!publicPaths.contains(options.path)) {
      final token = await store.accessToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final is401 = err.response?.statusCode == 401;
    if (!is401 || publicPaths.contains(opts.path) || opts.extra['retried'] == true) {
      return handler.next(err);
    }
    final refresh = await store.refreshToken;
    if (refresh == null) {
      onSessionExpired();
      return handler.next(err);
    }
    try {
      final res = await refreshDio.post<Map<String, dynamic>>('/v1/auth/refresh', data: {'refreshToken': refresh});
      final data = res.data!;
      await store.saveTokens(access: data['accessToken'] as String, refresh: data['refreshToken'] as String);
      opts.headers['Authorization'] = 'Bearer ${data['accessToken']}';
      opts.extra['retried'] = true;
      // Les exécutions de paiement portent une Idempotency-Key : le rejeu est sûr.
      final retried = await retryDio.fetch<dynamic>(opts);
      handler.resolve(retried);
    } catch (_) {
      await store.clearTokens();
      onSessionExpired();
      handler.next(err);
    }
  }
}

/// Convertit toute erreur Dio en [ApiFailure] (accessible via `DioException.error`).
class ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err.copyWith(error: ApiFailure.fromDio(err)));
  }
}
