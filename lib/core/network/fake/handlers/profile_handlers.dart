import '../fake_api.dart';

/// Préférences de canal, appareils connectés, jeton push.
void registerProfileHandlers(FakeApi api) {
  final db = api.db;
  const channels = {'SMS', 'EMAIL', 'WHATSAPP'};
  const platforms = {'ANDROID', 'IOS', 'WEB'};

  api.on('GET', '/v1/preferences', (_) => FakeResponse.ok({'channel': db.channelPreference}));

  api.on('PUT', '/v1/preferences', (r) {
    final channel = r.body['channel'];
    if (channel != null && !channels.contains(channel)) {
      return FakeResponse.error(400, 'VALIDATION_FAILED', 'Canal inconnu.', details: {'field': 'channel'});
    }
    db.channelPreference = channel as String?;
    return const FakeResponse.noContent();
  });

  api.on('GET', '/v1/devices', (_) => FakeResponse.ok({'items': db.devices}));

  api.on('DELETE', '/v1/devices/:id', (r) {
    final device = db.devices.where((d) => d['id'] == r.pathParams['id']).firstOrNull;
    if (device == null) return FakeResponse.error(404, 'NOT_FOUND', 'Appareil introuvable.');
    db.devices.remove(device);
    if (device['current'] == true) db.revokeAccessToken(r.bearer);
    return const FakeResponse.noContent();
  });

  api.on('POST', '/v1/devices/push-token', (r) {
    final token = r.body['token'];
    final platform = r.body['platform'];
    if (token is! String || token.isEmpty || !platforms.contains(platform)) {
      return FakeResponse.error(400, 'VALIDATION_FAILED', 'Jeton push ou plateforme invalide.');
    }
    db.pushToken = token;
    return const FakeResponse.noContent();
  });
}
