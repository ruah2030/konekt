import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../storage/app_prefs.dart';
import '../storage/secure_store.dart';
import 'fake/fake_api.dart';
import 'fake/fake_db.dart';
import 'interceptors.dart';

/// Émet un évènement quand la session ne peut plus être rafraîchie.
/// Le contrôleur d'auth l'écoute pour renvoyer vers l'écran de connexion.
final sessionExpiredProvider = Provider<StreamController<void>>((ref) {
  final c = StreamController<void>.broadcast();
  ref.onDispose(c.close);
  return c;
});

final appVersionProvider = Provider<String>((ref) => '2.0.0');

/// Faux backend partagé (mode `USE_FAKE_API`) avec le jeu de démo. Surchargé dans les tests.
final fakeApiProvider = Provider<FakeApi>((ref) {
  final prefs = ref.watch(appPrefsProvider);
  return FakeApi(
    db: FakeDb.demo(savedPin: prefs.fakePin, onPinChanged: prefs.setFakePin),
  );
});

final dioProvider = Provider<Dio>((ref) {
  final store = ref.watch(secureStoreProvider);
  final options = BaseOptions(
    baseUrl: Env.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
  );

  Dio build() {
    final d = Dio(options);
    d.interceptors.add(RequestHeadersInterceptor(store, appVersion: ref.watch(appVersionProvider)));
    return d;
  }

  final fake = Env.useFakeApi ? ref.watch(fakeApiProvider) : null;
  final refreshDio = build();
  final retryDio = build();
  final dio = build();
  if (fake != null) {
    for (final d in [refreshDio, retryDio, dio]) {
      d.interceptors.add(FakeApiInterceptor(fake));
    }
  }
  dio.interceptors.insert(
    0,
    AuthInterceptor(
      store: store,
      refreshDio: refreshDio,
      retryDio: retryDio,
      onSessionExpired: () => ref.read(sessionExpiredProvider).add(null),
    ),
  );
  dio.interceptors.add(ErrorMappingInterceptor());
  if (Env.logNetwork && kDebugMode) {
    // Jamais en prod : les corps de requêtes peuvent contenir PIN/OTP.
    dio.interceptors.add(LogInterceptor(requestBody: false, responseBody: false));
  }
  return dio;
});
