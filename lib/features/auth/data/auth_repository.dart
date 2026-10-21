import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/domain/json.dart';
import '../../../core/domain/session.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/auth_models.dart';

/// Authentification du porteur (`/auth/customer/*`, guide Partie 2).
class AuthRepository {
  AuthRepository(this._dio, this._store, this._prefs);
  final Dio _dio;
  final SecureStore _store;
  final AppPrefs _prefs;

  Future<Json> _post(String path, [Object? data]) async =>
      (await _dio.post<Map<String, dynamic>>(path, data: data)).data ?? const {};

  /// Identifiant de carte : chiffres uniquement, espaces retirés.
  static String normalizeCardId(String raw) => raw.replaceAll(RegExp(r'\s+'), '');

  /// `GET /auth/customer/channels`. En cas d'échec, tous les canaux sont proposés.
  Future<ChannelAvailability> channels() async {
    try {
      return ChannelAvailability.fromJson((await _dio.get<Map<String, dynamic>>('/auth/customer/channels')).data!);
    } on DioException {
      return ChannelAvailability.fallback;
    }
  }

  /// `POST /auth/customer/login/init` : envoie le code de connexion.
  Future<LoginChallenge> loginInit({required String cardId, required String last4, OtpChannel? channel}) async {
    final cardCustomerId = normalizeCardId(cardId);
    final j = await _post('/auth/customer/login/init', {
      'cardCustomerId': cardCustomerId,
      'last4Digits': last4,
      'doubleAuthMethod': ?channel?.api,
      'appId': Env.appId,
    });
    return LoginChallenge.fromInit(j, cardCustomerId: cardCustomerId, last4Digits: last4, channel: channel);
  }

  /// `POST /auth/customer/login/confirm` : ouvre la session, enregistre jetons et carte.
  /// Le code d'invitation saisi à l'onboarding est transmis comme `merchantReferralCode`.
  Future<CardSession> loginConfirm(LoginChallenge challenge, String code) async {
    final referral = _prefs.referralCode;
    final j = await _post('/auth/customer/login/confirm', {
      'cardCustomerId': challenge.cardCustomerId,
      'last4Digits': challenge.last4Digits,
      'appId': Env.appId,
      'code': code,
      'merchantReferralCode': ?referral,
      'device': await _device(),
    });
    final tokens = j.obj('tokens');
    await _store.saveTokens(session: tokens.str('sessionToken'), refresh: tokens.str('refreshToken'));
    final session = CardSession.fromLoginConfirm(j);
    await _store.saveCardSession(session);
    return session;
  }

  /// Session existante au démarrage ? Test par `GET /cards` (401 → refresh → sinon déconnexion).
  Future<CardSession?> restore() async {
    final session = await _store.cardSession;
    if (session == null || await _store.sessionToken == null) return null;
    try {
      await _dio.get<Map<String, dynamic>>('/cards');
      return await _store.cardSession;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) {
        await _store.clear();
        return null;
      }
      // Réseau coupé ou émetteur injoignable : on garde la session, les écrans afficheront l'erreur.
      return session;
    }
  }

  Future<void> markPinCreated() async {
    final s = await _store.cardSession;
    if (s != null) await _store.saveCardSession(s.copyWith(hasPin: true));
  }

  /// `POST /auth/customer/logout`. Jetons effacés même si l'appel échoue.
  Future<void> logout() async {
    try {
      await _dio.post<void>('/auth/customer/logout');
    } finally {
      await _store.clear();
    }
  }

  /// `POST /auth/customer/logout-all` (téléphone perdu). Renvoie le nombre de sessions fermées.
  Future<int> logoutAll() async {
    try {
      return (await _post('/auth/customer/logout-all')).intOrNull('closed') ?? 0;
    } finally {
      await _store.clear();
    }
  }

  /// Objet `device` de `login/confirm` (sans lui : ni push ni liste d'appareils fiable).
  Future<Map<String, String>> _device() async {
    if (kIsWeb) return {'type': 'WEB', 'label': 'Navigateur web'};
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return {'type': 'ANDROID', 'label': _clip('${a.manufacturer} ${a.model}')};
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return {'type': 'IOS', 'label': _clip(i.name)};
      }
    } catch (_) {}
    return {'type': 'ANDROID', 'label': 'Téléphone'};
  }

  static String _clip(String s) => s.length > 80 ? s.substring(0, 80) : s;
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioProvider), ref.watch(secureStoreProvider), ref.watch(appPrefsProvider)),
);
