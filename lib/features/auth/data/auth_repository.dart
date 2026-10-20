import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/json.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/auth_models.dart';

class AuthRepository {
  AuthRepository(this._dio, this._store);
  final Dio _dio;
  final SecureStore _store;

  Future<Json> _post(String path, [Object? data]) async =>
      (await _dio.post<Map<String, dynamic>>(path, data: data)).data ?? const {};

  /// Renvoie le prénom de la personne qui a invité.
  Future<String> verifyInvitation(String code) async =>
      (await _post('/v1/invitations/verify', {'code': code.replaceAll('-', '')})).str('inviterName');

  /// Renvoie la position sur la liste d'attente.
  Future<int> joinWaitlist(String msisdn) async =>
      (await _post('/v1/waitlist', {'msisdn': msisdn})).integer('position');

  Future<LoginChallenge> login({required String cardId, required String last4, required OtpChannel channel}) async =>
      LoginChallenge.fromJson(
        await _post('/v1/auth/login', {'cardId': cardId, 'last4': last4, 'channel': channel.api}),
      );

  Future<LoginChallenge> resendOtp(String challengeId) async =>
      LoginChallenge.fromJson(await _post('/v1/auth/otp/resend', {'challengeId': challengeId}));

  /// Valide l'OTP, enregistre les tokens et renvoie `hasPin`.
  Future<bool> verifyOtp({required String challengeId, required String code}) async {
    final j = await _post('/v1/auth/otp/verify', {
      'challengeId': challengeId,
      'code': code,
      'device': await _deviceInfo(),
    });
    await _store.saveTokens(access: j.str('accessToken'), refresh: j.str('refreshToken'));
    return j.boolean('hasPin');
  }

  /// Session existante au démarrage ? Renvoie `hasPin`, ou `null` si non connecté.
  Future<bool?> restore() async {
    if (await _store.accessToken == null) return null;
    try {
      final j = (await _dio.get<Map<String, dynamic>>('/v1/auth/session')).data!;
      return j.boolean('hasPin');
    } on DioException {
      await _store.clearTokens();
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post<void>('/v1/auth/logout');
    } finally {
      await _store.clearTokens();
    }
  }

  /// Renvoie le nombre de sessions fermées.
  Future<int> logoutAll() async {
    try {
      return (await _post('/v1/auth/logout-all')).intOrNull('closedSessions') ?? 0;
    } finally {
      await _store.clearTokens();
    }
  }

  Future<Map<String, String>> _deviceInfo() async {
    if (kIsWeb) return {'label': 'Navigateur web', 'platform': 'WEB'};
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return {'label': '${a.manufacturer} ${a.model}', 'platform': 'ANDROID'};
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return {'label': i.utsname.machine, 'platform': 'IOS'};
      }
    } catch (_) {}
    return {'label': 'Appareil', 'platform': 'ANDROID'};
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioProvider), ref.watch(secureStoreProvider)),
);
