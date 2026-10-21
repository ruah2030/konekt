import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../domain/profile_models.dart';

/// Préférences de notification (§2.9), appareils connectés et jeton push (§2.8).
class ProfileRepository {
  ProfileRepository(this._dio);
  final Dio _dio;

  /// `GET /auth/customer/preferences` → canal préféré (`null` = Auto).
  Future<MessageChannel> preferredChannel() async {
    final res = await _dio.get<Map<String, dynamic>>('/auth/customer/preferences');
    return MessageChannel.fromApi(res.data!['preferredChannel'] as String?);
  }

  /// `PATCH /auth/customer/preferences`. [MessageChannel.auto] envoie `null` (retour à l'ordre par défaut).
  /// 409 : carte sans dossier chez nous (vendue ailleurs), aucune préférence possible.
  Future<MessageChannel> setPreferredChannel(MessageChannel channel) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/auth/customer/preferences',
      data: <String, dynamic>{'preferredChannel': channel.api},
    );
    final data = res.data;
    return data != null && data.containsKey('preferredChannel')
        ? MessageChannel.fromApi(data['preferredChannel'] as String?)
        : channel;
  }

  /// `GET /auth/customer/devices`.
  Future<List<Device>> devices() async {
    final res = await _dio.get<dynamic>('/auth/customer/devices');
    final data = res.data;
    final raw = switch (data) {
      List() => data,
      Map() => (data['devices'] ?? data['data'] ?? const []) as List,
      _ => const [],
    };
    return raw.map((e) => Device.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// `DELETE /auth/customer/devices/:deviceId` : effet immédiat. Pour l'appareil courant, la session
  /// appelante est fermée (l'app doit alors revenir à l'écran de connexion).
  Future<DeviceDisconnection> disconnectDevice(String deviceId) async {
    final res = await _dio.delete<Map<String, dynamic>>('/auth/customer/devices/${Uri.encodeComponent(deviceId)}');
    return DeviceDisconnection.fromJson(res.data ?? const {});
  }

  /// `POST /auth/customer/devices/push-token` (≤ 512 caractères), dès que Firebase délivre ou renouvelle un jeton.
  /// 403 si la session n'a pas d'appareil (il faut transmettre `device` à `login/confirm`).
  Future<void> registerPushToken(String fcmToken) =>
      _dio.post<void>('/auth/customer/devices/push-token', data: {'fcmToken': fcmToken});
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(dioProvider)));
