import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/profile_repository.dart';
import '../../domain/profile_models.dart';

/// Canal de réception des messages (rechargé à chaque ouverture : pas de cache entre sessions).
final channelPreferenceProvider = AsyncNotifierProvider.autoDispose<ChannelPreferenceController, MessageChannel>(
  ChannelPreferenceController.new,
);

class ChannelPreferenceController extends AsyncNotifier<MessageChannel> {
  @override
  Future<MessageChannel> build() => ref.watch(profileRepositoryProvider).preferredChannel();

  /// Mise à jour optimiste ; restaure la valeur précédente en cas d'erreur (relancée).
  Future<void> select(MessageChannel channel) async {
    final previous = state.value;
    state = AsyncData(channel);
    try {
      state = AsyncData(await ref.read(profileRepositoryProvider).setPreferredChannel(channel));
    } catch (_) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

/// Appareils connectés à la carte.
final devicesProvider = AsyncNotifierProvider.autoDispose<DevicesController, List<Device>>(DevicesController.new);

class DevicesController extends AsyncNotifier<List<Device>> {
  @override
  Future<List<Device>> build() => ref.watch(profileRepositoryProvider).devices();

  /// Déconnecte l'appareil : ses sessions sont fermées, il reste listé sans session active.
  Future<DeviceDisconnection> disconnect(String deviceId) async {
    final result = await ref.read(profileRepositoryProvider).disconnectDevice(deviceId);
    state = AsyncData([
      for (final d in state.value ?? const <Device>[])
        d.deviceId == deviceId ? d.copyWith(hasActiveSession: false, notificationsEnabled: false) : d,
    ]);
    return result;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(profileRepositoryProvider).devices());
  }
}

/// Version affichée en pied de profil (« 2.0 »). Repli sur [appVersionProvider] si le plugin est absent.
final displayVersionProvider = FutureProvider<String>((ref) async {
  var version = ref.watch(appVersionProvider);
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) version = info.version;
  } catch (_) {
    // Tests / plateformes sans plugin : version de configuration.
  }
  final parts = version.split('.');
  return parts.length >= 2 ? '${parts[0]}.${parts[1]}' : version;
});
