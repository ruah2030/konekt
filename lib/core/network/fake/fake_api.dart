import 'dart:async';

import 'package:dio/dio.dart';

import 'fake_db.dart';
import 'handlers/account_handlers.dart';
import 'handlers/auth_handlers.dart';
import 'handlers/card_handlers.dart';
import 'handlers/payment_handlers.dart';
import 'handlers/pin_handlers.dart';
import 'handlers/profile_handlers.dart';

/// Réponse d'un handler du faux backend.
class FakeResponse {
  const FakeResponse(this.status, [this.body]);
  const FakeResponse.ok([Object? body]) : this(200, body);
  const FakeResponse.created([Object? body]) : this(201, body);

  /// Erreur au format unique de l'API (guide §1.5) :
  /// `{ statusCode, code, message, details, timestamp, path, requestId }` (path/requestId ajoutés à l'envoi).
  factory FakeResponse.error(int status, String code, String message, {Map<String, dynamic>? details}) =>
      FakeResponse(status, <String, dynamic>{
        'statusCode': status,
        'code': code,
        'message': message,
        'details': ?details,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

  /// 400 `VALIDATION_FAILED` avec messages par champ.
  factory FakeResponse.validation(Map<String, List<String>> fields) => FakeResponse.error(
    400,
    'VALIDATION_FAILED',
    'Certains champs sont invalides. Le détail figure dans « details ».',
    details: fields,
  );

  final int status;
  final Object? body;
}

class FakeRequest {
  FakeRequest(this.options, this.pathParams);
  final RequestOptions options;
  final Map<String, String> pathParams;

  Map<String, dynamic> get body => options.data is Map ? Map<String, dynamic>.from(options.data as Map) : const {};
  Map<String, dynamic> get query => options.queryParameters;
  String? get bearer {
    final h = options.headers['Authorization'] as String?;
    return h != null && h.startsWith('Bearer ') ? h.substring(7) : null;
  }
}

typedef FakeHandler = FutureOr<FakeResponse> Function(FakeRequest req);

class _Route {
  _Route(this.method, String pattern, this.handler, this.auth, this.fields)
    : segments = pattern.split('/').where((s) => s.isNotEmpty).toList();
  final String method;
  final List<String> segments;
  final FakeHandler handler;
  final bool auth;
  final Set<String>? fields;

  Map<String, String>? match(String method, String path) {
    if (method != this.method) return null;
    final parts = path.split('?').first.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length != segments.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < parts.length; i++) {
      final s = segments[i];
      if (s.startsWith(':')) {
        params[s.substring(1)] = Uri.decodeComponent(parts[i]);
      } else if (s != parts[i]) {
        return null;
      }
    }
    return params;
  }
}

/// Faux backend en mémoire qui implémente le contrat de l'API CardConnect v2
/// (`docs/GUIDE-INTEGRATION-KONEKT.md`). Les chemins sont relatifs à `/api/v1`.
/// Il sert au développement tant que l'API n'est pas branchée, et aux tests.
class FakeApi {
  FakeApi({FakeDb? db, this.latency = const Duration(milliseconds: 600)}) : db = db ?? FakeDb() {
    registerAccountHandlers(this);
    registerAuthHandlers(this);
    registerPinHandlers(this);
    registerPaymentHandlers(this);
    registerCardHandlers(this);
    registerProfileHandlers(this);
  }

  final FakeDb db;
  final Duration latency;
  final _routes = <_Route>[];

  /// [auth] : exige un Bearer valide. [fields] : champs de corps autorisés ; comme l'API réelle,
  /// tout champ inconnu donne 400 `VALIDATION_FAILED` (« property X should not exist »).
  void on(String method, String pattern, FakeHandler handler, {bool auth = true, Set<String>? fields}) =>
      _routes.add(_Route(method, pattern, handler, auth, fields));

  Future<FakeResponse> handle(RequestOptions o) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    for (final r in _routes) {
      final params = r.match(o.method, o.path);
      if (params == null) continue;
      final req = FakeRequest(o, params);
      if (r.auth) {
        final bearer = req.bearer;
        if (bearer == null) {
          return FakeResponse.error(401, 'UNAUTHENTICATED', 'Authentification requise.');
        }
        if (!db.isValidSessionToken(bearer)) {
          return FakeResponse.error(401, 'SESSION_EXPIRED', 'Session fermée ou expirée.');
        }
      }
      final allowed = r.fields;
      if (allowed != null) {
        final unknown = req.body.keys.where((k) => !allowed.contains(k)).toList();
        if (unknown.isNotEmpty) {
          return FakeResponse.validation({
            for (final k in unknown) k: ['property $k should not exist'],
          });
        }
      }
      return r.handler(req);
    }
    return FakeResponse.error(404, 'NOT_FOUND', 'Route inconnue du faux backend : ${o.method} ${o.path}');
  }
}

/// Branche le [FakeApi] dans Dio : aucune requête ne sort du téléphone.
class FakeApiInterceptor extends Interceptor {
  FakeApiInterceptor(this.api);
  final FakeApi api;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final res = await api.handle(options);
    final body = res.body;
    if (body is Map && body['code'] is String && res.status >= 400) {
      body['path'] ??= '/api/v1${options.path}';
      body['requestId'] ??= options.headers['X-Request-Id'];
    }
    final response = Response<dynamic>(requestOptions: options, statusCode: res.status, data: body);
    if (res.status >= 400) {
      handler.reject(
        DioException.badResponse(statusCode: res.status, requestOptions: options, response: response),
        true,
      );
    } else {
      handler.resolve(response, true);
    }
  }
}
