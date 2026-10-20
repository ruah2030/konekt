import '../../../core/domain/json.dart';

/// Canal préféré pour les messages (un seul message par événement). [auto] = choix du serveur.
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

enum DevicePlatform {
  android('ANDROID', 'Android'),
  ios('IOS', 'iOS'),
  web('WEB', 'Web');

  const DevicePlatform(this.api, this.label);
  final String api;
  final String label;

  static DevicePlatform fromApi(String v) => values.firstWhere((p) => p.api == v, orElse: () => DevicePlatform.web);
}

/// Appareil connecté à la carte.
class Device {
  const Device({
    required this.id,
    required this.label,
    required this.platform,
    required this.current,
    required this.lastSeenAt,
  });

  factory Device.fromJson(Json j) => Device(
    id: j.str('id'),
    label: j.str('label'),
    platform: DevicePlatform.fromApi(j.str('platform')),
    current: j.boolean('current'),
    lastSeenAt: j.date('lastSeenAt'),
  );

  final String id;
  final String label;
  final DevicePlatform platform;

  /// L'appareil qui fait la requête.
  final bool current;
  final DateTime lastSeenAt;
}
