import '../../../core/domain/json.dart';

/// Canal préféré pour les messages (guide §2.9) : un seul message par événement, les autres en repli.
/// [auto] (`null` côté API) = ordre par défaut (SMS, puis courriel, puis WhatsApp).
enum MessageChannel {
  sms('SMS', 'SMS'),
  email('EMAIL', 'E-mail'),
  whatsapp('WHATSAPP', 'WhatsApp'),
  auto(null, 'Auto');

  const MessageChannel(this.api, this.label);
  final String? api;
  final String label;

  static MessageChannel fromApi(String? v) => values.firstWhere((c) => c.api == v, orElse: () => MessageChannel.auto);
}

/// `DeviceType` de l'API.
enum DeviceType {
  android('ANDROID', 'Android'),
  ios('IOS', 'iOS'),
  web('WEB', 'Web'),
  other('OTHER', 'Appareil');

  const DeviceType(this.api, this.label);
  final String api;
  final String label;

  static DeviceType fromApi(String? v) => values.firstWhere((p) => p.api == v, orElse: () => DeviceType.other);
}

/// Appareil de `GET /auth/customer/devices` (guide §2.8).
class Device {
  const Device({
    required this.deviceId,
    required this.type,
    required this.label,
    required this.isCurrent,
    required this.hasActiveSession,
    required this.notificationsEnabled,
    this.lastSeenAt,
    this.lastIpAddress,
    this.firstSeenAt,
  });

  factory Device.fromJson(Json j) {
    final type = DeviceType.fromApi(j.strOrNull('type'));
    final label = j.strOrNull('label');
    return Device(
      deviceId: j.str('deviceId'),
      type: type,
      label: label == null || label.isEmpty ? type.label : label,
      isCurrent: j.boolean('isCurrent'),
      hasActiveSession: j.boolean('hasActiveSession'),
      notificationsEnabled: j.boolean('notificationsEnabled'),
      lastSeenAt: j.dateOrNull('lastSeenAt'),
      lastIpAddress: j.strOrNull('lastIpAddress'),
      firstSeenAt: j.dateOrNull('firstSeenAt'),
    );
  }

  final String deviceId;
  final DeviceType type;
  final String label;

  /// Appareil qui fait la requête (« Cet appareil »).
  final bool isCurrent;
  final bool hasActiveSession;
  final bool notificationsEnabled;
  final DateTime? lastSeenAt;
  final String? lastIpAddress;
  final DateTime? firstSeenAt;

  Device copyWith({bool? hasActiveSession, bool? notificationsEnabled}) => Device(
    deviceId: deviceId,
    type: type,
    label: label,
    isCurrent: isCurrent,
    hasActiveSession: hasActiveSession ?? this.hasActiveSession,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    lastSeenAt: lastSeenAt,
    lastIpAddress: lastIpAddress,
    firstSeenAt: firstSeenAt,
  );
}

/// Réponse de `DELETE /auth/customer/devices/:deviceId`.
class DeviceDisconnection {
  const DeviceDisconnection({required this.deviceId, required this.closedSessions, this.message});

  factory DeviceDisconnection.fromJson(Json j) => DeviceDisconnection(
    deviceId: j.strOrNull('deviceId') ?? '',
    closedSessions: j.intOrNull('closedSessions') ?? 0,
    message: j.strOrNull('message'),
  );

  final String deviceId;
  final int closedSessions;
  final String? message;
}
