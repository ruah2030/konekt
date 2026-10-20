import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/design_system/theme/app_colors.dart';
import 'package:konekt/features/account/presentation/account_providers.dart';
import 'package:konekt/features/notifications/presentation/screens/notifications_screen.dart';

import '../../helpers/test_app.dart';

Color dotColor(WidgetTester tester, String id) =>
    (tester.widget<Container>(find.byKey(Key('notif-dot-$id'))).decoration! as BoxDecoration).color!;

int unread(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(NotificationsScreen))).read(unreadCountProvider);

void main() {
  testWidgets('liste : non lues mises en avant, tap = lu', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    await env.pumpScreen(tester, const NotificationsScreen());
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Envoi effectué'), findsOneWidget);
    expect(find.text('Retrait échoué'), findsOneWidget);
    expect(find.text('Nouvelle connexion'), findsOneWidget);
    expect(unread(tester), 2);

    final first = env.db.notifications.first;
    final id = first['id'] as String;
    expect(dotColor(tester, id), KColors.warning);

    await tester.tap(find.text('Envoi effectué'));
    await tester.pumpAndSettle();
    expect(dotColor(tester, id), const Color(0xFFCBD5E1));
    expect(first['read'], isTrue);
    expect(unread(tester), 1);
  });

  testWidgets('tout marquer comme lu → 0 non lu', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    await env.pumpScreen(tester, const NotificationsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tout marquer comme lu'));
    await tester.pumpAndSettle();
    expect(unread(tester), 0);
    expect(env.db.notifications.every((n) => n['read'] == true), isTrue);
    for (final n in env.db.notifications) {
      expect(dotColor(tester, n['id'] as String), const Color(0xFFCBD5E1));
    }
  });

  testWidgets('état vide', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    env.db.notifications.clear();
    await env.pumpScreen(tester, const NotificationsScreen());
    await tester.pumpAndSettle();
    expect(find.text("Aucune notification pour l'instant."), findsOneWidget);
  });

  testWidgets('pull-to-refresh affiche les nouvelles notifications', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    await env.pumpScreen(tester, const NotificationsScreen());
    await tester.pumpAndSettle();
    env.db.addNotification('Recharge réussie', '10 000 FCFA crédités.');
    await tester.fling(find.text('Envoi effectué'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Recharge réussie'), findsOneWidget);
    expect(unread(tester), 3);
  });

  testWidgets('erreur de chargement (session absente) puis affichage de l’erreur', (tester) async {
    final env = await TestEnv.create();
    await env.pumpScreen(tester, const NotificationsScreen());
    await tester.pumpAndSettle();
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
