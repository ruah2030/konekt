import '../fake_api.dart';

/// Appareils connectés (guide §2.8) et préférences de notification (§2.9).
void registerProfileHandlers(FakeApi api) {
  final db = api.db;

  // ---- §2.9 Préférences ----
  api.on('GET', '/auth/customer/preferences', (_) {
    return FakeResponse.ok({'success': true, 'preferredChannel': db.isExternalCard ? null : db.preferredChannel});
  });

  api.on('PATCH', '/auth/customer/preferences', (r) {
    final b = r.body;
    if (b.containsKey('preferredChannel')) {
      final v = b['preferredChannel'];
      if (v != null && !const {'SMS', 'EMAIL', 'WHATSAPP'}.contains(v)) {
        return FakeResponse.validation({
          'preferredChannel': ['preferredChannel must be one of the following values: SMS, EMAIL, WHATSAPP'],
        });
      }
      if (db.isExternalCard) {
        return FakeResponse.error(
          409,
          'CONFLICT',
          'Cette carte n’a pas de dossier chez nous : aucune préférence de canal ne peut être enregistrée.',
        );
      }
      db.preferredChannel = v as String?;
    }
    return FakeResponse.ok({'success': true, 'preferredChannel': db.preferredChannel});
  }, fields: const {'preferredChannel'});

  // ---- §2.8 Appareils ----
  api.on('GET', '/auth/customer/devices', (_) {
    return FakeResponse.ok({
      'success': true,
      'devices': [for (final d in db.devices) Map<String, dynamic>.from(d)],
    });
  });

  api.on('DELETE', '/auth/customer/devices/:deviceId', (r) {
    final device = db.devices.where((d) => d['deviceId'] == r.pathParams['deviceId']).firstOrNull;
    if (device == null) {
      return FakeResponse.error(404, 'NOT_FOUND', 'Appareil introuvable.');
    }
    final closed = device['hasActiveSession'] == true ? 1 : 0;
    device
      ..['hasActiveSession'] = false
      ..['notificationsEnabled'] = false;
    // Effet immédiat : si c'est l'appareil courant, le jeton appelant ne vaut plus rien.
    if (device['isCurrent'] == true) db.revokeSessionToken(r.bearer);
    return FakeResponse.ok({
      'success': true,
      'deviceId': device['deviceId'],
      'closedSessions': closed,
      'message': 'Appareil déconnecté : ses sessions ont été fermées.',
    });
  });

  api.on('POST', '/auth/customer/devices/push-token', (r) {
    final token = r.body['fcmToken'];
    if (token is! String || token.isEmpty || token.length > 512) {
      return FakeResponse.validation({
        'fcmToken': ['fcmToken must be shorter than or equal to 512 characters'],
      });
    }
    final current = db.devices.where((d) => d['isCurrent'] == true).firstOrNull;
    if (current == null) {
      return FakeResponse.error(
        403,
        'FORBIDDEN',
        'Aucun appareil n’est rattaché à cette session : reconnectez-vous en transmettant « device ».',
      );
    }
    db.pushToken = token;
    current['notificationsEnabled'] = true;
    return const FakeResponse.ok({'success': true});
  }, fields: const {'fcmToken'});
}
