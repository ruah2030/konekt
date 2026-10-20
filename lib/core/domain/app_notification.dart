import 'json.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromJson(Json j) => AppNotification(
    id: j.str('id'),
    title: j.str('title'),
    body: j.str('body'),
    createdAt: j.date('createdAt'),
    read: j.boolean('read'),
  );

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  AppNotification markRead() => AppNotification(id: id, title: title, body: body, createdAt: createdAt, read: true);
}
