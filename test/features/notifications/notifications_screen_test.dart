import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/app_notification.dart';
import 'package:konekt/features/account/data/account_repository.dart';
import 'package:konekt/features/account/presentation/account_providers.dart';
import 'package:konekt/features/notifications/presentation/screens/notifications_screen.dart';

import '../../helpers/test_app.dart';
import '../history/query_recorder.dart';
import '../home/home_test_utils.dart';

int unreadInDb(TestEnv env) => env.db.notifications.where((n) => n['readAt'] == null && n['archivedAt'] == null).length;

/// Pastille telle que l'accueil la lit (`GET /notifications/unread-count`).
Future<int?> badge(WidgetTester tester) async {
  final c = ProviderScope.containerOf(tester.element(find.byType(NotificationsScreen)));
  c.read(unreadCountProvider);
  await settle(tester, 2);
  return c.read(unreadCountProvider).value;
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(NotificationsScreen)));

/// Ajoute [n] messages non lus (plus anciens que ceux du jeu de démo).
void addMany(TestEnv env, int n) {
  for (var i = 0; i < n; i++) {
    env.db.addNotification('Message $i', 'Contenu $i', at: DateTime(2026, 1, 1).subtract(Duration(hours: i)));
  }
  // `addNotification` insère en tête : on remet le tri par date décroissante de l'API.
  env.db.notifications.sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
}

void main() {
  testWidgets('affiche titre, message et icône selon le kind', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    env.db.addNotification('Alerte', 'Votre solde est bas.', kind: 'WARNING');
    await pumpRouted(tester, env, const NotificationsScreen());

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Envoi effectué'), findsOneWidget);
    expect(find.text('50 000 FCFA envoyés à Afiavi Sossou.'), findsOneWidget);
    expect(find.text('Votre solde est bas.'), findsOneWidget);
    final warning = env.db.notifications.first['id'];
    expect(find.byKey(Key('notif-kind-warning-$warning')), findsOneWidget);
    final security = env.db.notifications.last['id'];
    expect(find.byKey(Key('notif-kind-security-$security')), findsOneWidget);
    // Messages liés à une opération : lien vers le reçu.
    expect(find.text('Voir le reçu'), findsNWidgets(2));
  });

  testWidgets('tap sur un message lié à une opération : lu puis reçu', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    final notif = env.db.notifications.firstWhere((n) => n['title'] == 'Envoi effectué');
    final opId = notif['linkId'];
    await pumpRouted(tester, env, const NotificationsScreen());

    await tester.tap(find.text('Envoi effectué'));
    await settle(tester);

    expect(find.text('Reçu $opId history'), findsOneWidget);
    expect(notif['readAt'], isNotNull);
  });

  testWidgets('tap sur un message sans lien : marqué lu, pas de navigation', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    env.db.addNotification('Info', 'Nouveautés disponibles.');
    final id = env.db.notifications.first['id'];
    await pumpRouted(tester, env, const NotificationsScreen());
    expect(find.byKey(Key('notif-dot-$id')), findsOneWidget);

    await tester.tap(find.text('Nouveautés disponibles.'));
    await settle(tester);

    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byKey(Key('notif-dot-$id')), findsNothing);
    expect(env.db.notifications.first['readAt'], isNotNull);
  });

  testWidgets('tout marquer comme lu : pastille à 0', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    await pumpRouted(tester, env, const NotificationsScreen());
    expect(await badge(tester), 2);

    await tester.tap(find.byKey(const Key('notifs-read-all')));
    await settle(tester);

    expect(unreadInDb(env), 0);
    expect(find.byKey(const Key('notifs-read-all')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('notif-dot-'),
      ),
      findsNothing,
    );
    expect(await badge(tester), 0);
  });

  testWidgets('ranger un message (balayage)', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    final notif = env.db.notifications.firstWhere((n) => n['title'] == 'Retrait échoué');
    await pumpRouted(tester, env, const NotificationsScreen());

    await tester.drag(find.byKey(Key('notif-${notif['id']}')), const Offset(-600, 0));
    await settle(tester, 8);

    expect(find.text('Retrait échoué'), findsNothing);
    expect(find.text('Notification rangée.'), findsOneWidget);
    expect(notif['archivedAt'], isNotNull);
    expect(await badge(tester), 1);

    // Pull-to-refresh : le serveur ne renvoie plus le message rangé.
    await tester.fling(find.byKey(const Key('notifs-list')), const Offset(0, 400), 1000);
    await settle(tester, 10);
    expect(find.text('Retrait échoué'), findsNothing);
    expect(find.text('Envoi effectué'), findsOneWidget);
  });

  testWidgets('aucune notification', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    env.db.notifications.clear();
    await pumpRouted(tester, env, const NotificationsScreen());
    expect(find.byKey(const Key('notifs-empty')), findsOneWidget);
  });

  testWidgets('pagination par 20 : chargement au défilement', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    addMany(env, 45); // 48 messages au total
    await pumpRouted(tester, env, const NotificationsScreen());
    final c = containerOf(tester);
    final rec = QueryRecorder.attach(c);

    expect(c.read(notificationsProvider).value!.items, hasLength(20));
    expect(c.read(notificationsProvider).value!.hasMore, isTrue);

    for (var i = 0; i < 4 && c.read(notificationsProvider).value!.hasMore; i++) {
      await tester.drag(find.byKey(const Key('notifs-list')), const Offset(0, -4000));
      await settle(tester);
    }
    expect(rec.queries('/notifications'), [
      {'page': 2, 'limit': 20},
      {'page': 3, 'limit': 20},
    ]);
    final state = c.read(notificationsProvider).value!;
    expect(state.items, hasLength(48));
    expect(state.items.map((n) => n.id).toSet(), hasLength(48));
    expect(state.hasMore, isFalse);
    expect(find.byKey(const Key('notifs-more')), findsNothing);
    // Pastille : `unreadCount` de la réponse (indépendant de la pagination).
    expect(state.unreadCount, unreadInDb(env));
    expect(find.text('Non lues (${unreadInDb(env)})'), findsOneWidget);
  });

  testWidgets('pagination : bouton « Voir plus »', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    addMany(env, 22); // 25 messages
    await pumpRouted(tester, env, const NotificationsScreen());
    tester.view.physicalSize = const Size(900, 6000);
    await settle(tester);
    final c = containerOf(tester);
    final rec = QueryRecorder.attach(c);
    expect(c.read(notificationsProvider).value!.items, hasLength(20));

    await tester.tap(find.byKey(const Key('notifs-more')));
    await settle(tester);
    expect(rec.queries('/notifications'), [
      {'page': 2, 'limit': 20},
    ]);
    expect(c.read(notificationsProvider).value!.items, hasLength(25));
    expect(find.text('Contenu 21'), findsOneWidget);
    expect(find.byKey(const Key('notifs-more')), findsNothing);
  });

  testWidgets('filtre « Non lues » : unreadOnly=true, puis retour à toutes', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    await pumpRouted(tester, env, const NotificationsScreen());
    final c = containerOf(tester);
    final rec = QueryRecorder.attach(c);
    final read = env.db.notifications.firstWhere((n) => n['readAt'] != null);
    expect(find.text(read['title'] as String), findsOneWidget);
    expect(find.text('Non lues (2)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifs-filter-unread')));
    await settle(tester);
    expect(rec.queries('/notifications').last, {'page': 1, 'limit': 20, 'unreadOnly': 'true'});
    expect(find.text(read['title'] as String), findsNothing);
    expect(find.text('Envoi effectué'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifs-read-all')));
    await settle(tester);
    expect(find.text('Non lues'), findsOneWidget);
    // Rafraîchissement : le filtre est conservé.
    unawaited(c.read(notificationsProvider.notifier).refresh());
    await settle(tester);
    expect(rec.queries('/notifications').last['unreadOnly'], 'true');
    expect(find.byKey(const Key('notifs-empty')), findsOneWidget);
    expect(find.text('Aucune notification non lue.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifs-filter-all')));
    await settle(tester);
    expect(rec.queries('/notifications').last.containsKey('unreadOnly'), isFalse);
    expect(find.text(read['title'] as String), findsOneWidget);
  });

  test('faux backend : filtre kind et validation', () async {
    final env = await TestEnv.create(signedIn: true);
    env.db.addNotification('Sécurité', 'Nouvel appareil.', kind: 'SECURITY');
    final c = env.container();
    addTearDown(c.dispose);
    await TestEnv.waitForAuth(c);
    final repo = c.read(accountRepositoryProvider);
    final page = await repo.notifications(kind: 'SECURITY');
    expect(page.items, isNotEmpty);
    expect(page.items.every((n) => n.kind == NotificationKind.security), isTrue);
    expect(page.unreadCount, unreadInDb(env));
    await expectLater(repo.notifications(kind: 'NOPE'), throwsA(anything));
  });
}
