import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../domain/profile_models.dart';

/// Préférences de canal, appareils connectés et jeton push.
class ProfileRepository {
  ProfileRepository(this._dio);
  final Dio _dio;

  Future<MessageChannel> channelPreference() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/preferences');
    return MessageChannel.fromApi(res.data!['channel'] as String?);
  }

  Future<void> setChannelPreference(MessageChannel channel) =>
      _dio.put<void>('/v1/preferences', data: {'channel': channel.api});

  Future<List<Device>> devices() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/devices');
    final items = (res.data!['items'] as List? ?? const []).cast<Map<dynamic, dynamic>>();
    return items.map((e) => Device.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// Ferme la session de l'appareil. Si c'est l'appareil courant, le jeton appelant est révoqué.
  Future<void> removeDevice(String id) => _dio.delete<void>('/v1/devices/${Uri.encodeComponent(id)}');

  /// Enregistre le jeton FCM/APNs de l'appareil (notifications push).
  Future<void> registerPushToken({required String token, required DevicePlatform platform}) =>
      _dio.post<void>('/v1/devices/push-token', data: {'token': token, 'platform': platform.api});
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(dioProvider)));
