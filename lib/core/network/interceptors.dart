import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../storage/secure_store.dart';
import 'api_failure.dart';

/// En-têtes recommandés (guide §1.3) : X-Request-Id (affiché « Réf. » dans les erreurs),
/// Accept-Language et User-Agent.
class RequestHeadersInterceptor extends Interceptor {
  RequestHeadersInterceptor({required this.userAgent});
  final String userAgent;
  static const _uuid = Uuid();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Request-Id'] ??= 'req_${_uuid.v4().replaceAll('-', '').substring(0, 16).toUpperCase()}';
    options.headers['Accept-Language'] = 'fr';
    options.headers['User-Agent'] = userAgent;
    handler.next(options);
  }
}

/// Ajoute le Bearer, renouvelle la session sur 401 `SESSION_EXPIRED` (un seul refresh à la fois,
/// les requêtes concurrentes attendent grâce à [QueuedInterceptor]) puis rejoue UNE fois.
///
/// Règles 401 (guide §1.6) :
/// - `SESSION_EXPIRED` → refresh puis rejeu ; échec du refresh → déconnexion ;
/// - `UNAUTHENTICATED` « Jeton non reconnu pour cette route » → bug d'intégration, PAS de déconnexion ;
/// - autre `UNAUTHENTICATED` sur une requête authentifiée → déconnexion.
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

  /// Routes appelées SANS `Authorization` (un jeton joint y est ignoré ou refusé).
  static const publicPaths = {
    '/auth/customer/channels',
    '/auth/customer/login/init',
    '/auth/customer/login/confirm',
    '/auth/customer/refresh',
    '/status',
  };

  static bool isPublic(String path) => publicPaths.contains(path) || path.startsWith('/card-display');

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!isPublic(options.path)) {
      final token = await store.sessionToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final body = err.response?.data;
    final code = body is Map ? body['code'] : null;
    final message = body is Map ? '${body['message'] ?? ''}' : '';
    final authenticated = opts.headers.containsKey('Authorization');
    if (err.response?.statusCode != 401 || !authenticated || isPublic(opts.path)) {
      return handler.next(err);
    }
    if (code == ErrorCodes.unauthenticated &&
        RegExp('non reconnu pour cette route', caseSensitive: false).hasMatch(message)) {
      return handler.next(err);
    }
    if (code != ErrorCodes.sessionExpired || opts.extra['retried'] == true) {
      await store.clear();
      onSessionExpired();
      return handler.next(err);
    }
    final refresh = await store.refreshToken;
    if (refresh == null) {
      await store.clear();
      onSessionExpired();
      return handler.next(err);
    }
    try {
      final res = await refreshDio.post<Map<String, dynamic>>(
        '/auth/customer/refresh',
        data: {'refreshToken': refresh},
      );
      final data = res.data!;
      await store.saveTokens(session: data['sessionToken'] as String, refresh: data['refreshToken'] as String);
      opts.headers['Authorization'] = 'Bearer ${data['sessionToken']}';
      opts.extra['retried'] = true;
      // Rejeu sûr : sur SESSION_EXPIRED le serveur n'a rien exécuté (recette §7.2).
      handler.resolve(await retryDio.fetch<dynamic>(opts));
    } catch (_) {
      await store.clear();
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
