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

/// Émet le message du serveur quand le renouvellement de session est refusé en 403 : la carte a été
/// bloquée depuis la connexion (guide §2.5). L'app affiche alors un écran d'information + support.
final cardBlockedProvider = Provider<StreamController<String>>((ref) {
  final c = StreamController<String>.broadcast();
  ref.onDispose(c.close);
  return c;
});

final appVersionProvider = Provider<String>((ref) => '2.0.0');

/// `CardKonekt/2.0.0 (Android)` — recommandé par le guide (§1.3).
final userAgentProvider = Provider<String>((ref) {
  final os = kIsWeb
      ? 'Web'
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'iOS'
      : 'Android';
  return 'CardKonekt/${ref.watch(appVersionProvider)} ($os)';
});

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
    // Les confirmations de paiement appellent l'émetteur dans la requête : délai long (≥ 60 s, §4.6).
    receiveTimeout: const Duration(seconds: 75),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
  );

  Dio build() {
    final d = Dio(options);
    d.interceptors.add(RequestHeadersInterceptor(userAgent: ref.watch(userAgentProvider)));
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
      onCardBlocked: (message) => ref.read(cardBlockedProvider).add(message),
    ),
  );
  dio.interceptors.add(ErrorMappingInterceptor());
  if (Env.logNetwork && kDebugMode) {
    // Jamais en prod : les corps de requêtes peuvent contenir PIN/OTP.
    dio.interceptors.add(LogInterceptor(requestBody: false, responseBody: false));
  }
  return dio;
});
