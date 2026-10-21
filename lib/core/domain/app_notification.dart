import 'json.dart';

/// `NotificationKind` : pilote la couleur et l'icône.
enum NotificationKind { info, success, warning, error, financial, security }

/// Message de la boîte in-app (`GET /notifications`, modèle `Notification`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.kind,
    required this.createdAt,
    this.readAt,
    this.linkType,
    this.linkId,
  });

  factory AppNotification.fromJson(Json j) => AppNotification(
    id: j.str('id'),
    title: j.strOrNull('title') ?? '',
    message: j.strOrNull('message') ?? '',
    kind: NotificationKind.values.asNameMap()[(j.strOrNull('kind') ?? 'INFO').toLowerCase()] ?? NotificationKind.info,
    createdAt: j.date('createdAt'),
    readAt: j.dateOrNull('readAt'),
    linkType: j.strOrNull('linkType'),
    linkId: j.strOrNull('linkId'),
  );

  final String id;
  final String title;

  /// Texte prêt à afficher : ne pas reformuler.
  final String message;
  final NotificationKind kind;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Liste ouverte (`operation`, `card`, …) : valeur inconnue → pas de lien.
  final String? linkType;
  final String? linkId;

  bool get read => readAt != null;

  /// Identifiant d'opération si le message pointe vers une opération.
  String? get operationId => linkType == 'operation' ? linkId : null;

  AppNotification markRead() => AppNotification(
    id: id,
    title: title,
    message: message,
    kind: kind,
    createdAt: createdAt,
    readAt: readAt ?? DateTime.now(),
    linkType: linkType,
    linkId: linkId,
  );
}
