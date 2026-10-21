import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/card/presentation/screens/card_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  Future<TestEnv> pump(WidgetTester tester, {String status = 'Active'}) async {
    tester.view
      ..physicalSize = const Size(1200, 3200)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = await TestEnv.create(signedIn: true, db: FakeDb(cardStatus: status, hasPin: true));
    await env.pumpScreen(tester, const CardScreen());
    await tester.pumpAndSettle();
    return env;
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();
  }

  testWidgets('affiche la carte, ses infos et les actions d’une carte active', (tester) async {
    await pump(tester);
    expect(find.text('Ma carte'), findsOneWidget);
    expect(find.text('•••• •••• •••• 4589'), findsOneWidget);
    expect(find.text('Virtual Standard - UBA BJ'), findsOneWidget);
    expect(find.text('UBA Bénin'), findsOneWidget);
    expect(find.text('121436474'), findsOneWidget);
    expect(find.byKey(const Key('card-action-view')), findsOneWidget);
    expect(find.byKey(const Key('card-action-suspend')), findsOneWidget);
    expect(find.byKey(const Key('card-action-lost')), findsOneWidget);
    expect(find.byKey(const Key('card-action-reactivate')), findsNothing);
  });

  testWidgets('suspendre (confirmation) → Inactive et action « Réactiver », puis réactiver', (tester) async {
    final env = await pump(tester);
    await tester.tap(find.byKey(const Key('card-action-suspend')));
    await tester.pumpAndSettle();
    expect(find.text('Suspendre ma carte ?'), findsOneWidget);
    await confirm(tester);

    expect(env.db.cardStatus, 'Inactive');
    expect(env.db.operations.first['amount'], 0);
    expect(find.text('Carte suspendue.'), findsOneWidget);
    expect(find.byKey(const Key('card-action-reactivate')), findsOneWidget);
    expect(find.byKey(const Key('card-action-suspend')), findsNothing);
    // Une carte suspendue reste affichable.
    expect(find.byKey(const Key('card-action-view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('card-action-reactivate')));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(env.db.cardStatus, 'Active');
    expect(find.byKey(const Key('card-action-suspend')), findsOneWidget);
  });

  testWidgets('annuler la confirmation ne change rien', (tester) async {
    final env = await pump(tester);
    await tester.tap(find.byKey(const Key('card-action-suspend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-cancel')));
    await tester.pumpAndSettle();
    expect(env.db.cardStatus, 'Active');
  });

  testWidgets('déclarer perdue depuis Active : avertissement définitif, puis carte bloquée + support', (tester) async {
    final env = await pump(tester);
    final ops = env.db.operations.length;
    await tester.tap(find.byKey(const Key('card-action-lost')));
    await tester.pumpAndSettle();
    expect(find.textContaining('DÉFINITIVE'), findsOneWidget);
    expect(find.textContaining('même si vous la retrouvez'), findsOneWidget);
    expect(find.textContaining('Vos fonds ne sont pas perdus'), findsOneWidget);
    expect(find.textContaining(lostFromSuspendedNotice), findsNothing);
    await confirm(tester);

    expect(env.db.cardStatus, 'LostOrStolen');
    expect(env.db.operations.length, ops + 1);
    expect(env.db.notifications.first['kind'], 'SECURITY');
    expect(find.byKey(const Key('card-action-suspend')), findsNothing);
    expect(find.byKey(const Key('card-action-lost')), findsNothing);
    expect(find.byKey(const Key('card-terminal-notice')), findsOneWidget);
    expect(find.byKey(const Key('card-support')), findsOneWidget);
  });

  testWidgets('déclarer perdue depuis Inactive : explication, puis deux appels (Active puis LostOrStolen)', (
    tester,
  ) async {
    final env = await pump(tester, status: 'Inactive');
    final ops = env.db.operations.length;
    await tester.tap(find.byKey(const Key('card-action-lost')));
    await tester.pumpAndSettle();
    expect(find.textContaining(lostFromSuspendedNotice), findsOneWidget);
    await confirm(tester);

    expect(env.db.cardStatus, 'LostOrStolen');
    expect(env.db.operations.length, ops + 2);
    expect(env.db.operations[1]['service']['label'], 'Réactivation de la carte');
    expect(env.db.operations[0]['service']['label'], 'Déclaration de perte ou de vol');
    expect(find.byKey(const Key('card-terminal-notice')), findsOneWidget);
  });

  testWidgets('carte pré-active : actions de statut masquées, affichage possible', (tester) async {
    await pump(tester, status: 'PreActive');
    expect(find.byKey(const Key('card-action-view')), findsOneWidget);
    expect(find.byKey(const Key('card-action-suspend')), findsNothing);
    expect(find.byKey(const Key('card-action-reactivate')), findsNothing);
    expect(find.byKey(const Key('card-action-lost')), findsNothing);
    expect(find.byKey(const Key('card-preactive-notice')), findsOneWidget);
  });

  testWidgets('carte désactivée : aucune action, support', (tester) async {
    await pump(tester, status: 'Deactivated');
    expect(find.byKey(const Key('card-action-suspend')), findsNothing);
    expect(find.byKey(const Key('card-action-lost')), findsNothing);
    await tester.tap(find.byKey(const Key('card-support')));
    await tester.pump();
    expect(find.textContaining('Support Konekt'), findsOneWidget);
  });
}
