import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:konekt/core/network/dio_client.dart';

/// Enregistre les requêtes envoyées au (faux) backend pour vérifier les paramètres de requête.
class QueryRecorder extends Interceptor {
  final calls = <RequestOptions>[];

  /// Branche l'enregistreur en tête du client Dio de [container].
  static QueryRecorder attach(ProviderContainer container) {
    final r = QueryRecorder();
    container.read(dioProvider).interceptors.insert(0, r);
    return r;
  }

  /// Paramètres des requêtes `GET` vers [path], dans l'ordre d'envoi.
  List<Map<String, dynamic>> queries(String path) => [
    for (final c in calls)
      if (c.method == 'GET' && c.path == path) c.queryParameters,
  ];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls.add(options);
    handler.next(options);
  }
}
