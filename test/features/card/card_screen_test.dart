import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/card/presentation/screens/card_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  Future<TestEnv> pump(WidgetTester tester, {String status = 'ACTIVE'}) async {
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = await TestEnv.create(signedIn: true, db: FakeDb(cardStatus: status));
    await env.pumpScreen(tester, const CardScreen());
    await tester.pumpAndSettle();
    return env;
  }

  double opacityOf(WidgetTester tester, String key) =>
      tester.widget<Opacity>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Opacity)).first).opacity;

  testWidgets('affiche la carte, les infos et les actions', (tester) async {
    await pump(tester);
    expect(find.text('Ma carte'), findsOneWidget);
    expect(find.text('•••• •••• •••• 4589'), findsOneWidget);
    expect(find.text('AWA HOUNGBÉDJI'), findsOneWidget);
    expect(find.text('VISA'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Visa Virtual Standard'), findsOneWidget);
    expect(find.text('UBA Bénin'), findsOneWidget);
    expect(find.text('121436474'), findsOneWidget);
    expect(find.text('Voir numéro et CVV'), findsOneWidget);
    expect(find.text('Suspendre ma carte'), findsOneWidget);
    expect(find.text('Déclarer perdue ou volée'), findsOneWidget);
    expect(opacityOf(tester, 'card-action-view'), 1);
  });

  testWidgets('suspendre via le dialogue → INACTIVE et action « Réactiver »', (tester) async {
    final env = await pump(tester);
    await tester.tap(find.byKey(const Key('card-action-suspend')));
    await tester.pumpAndSettle();
    expect(find.text('Suspendre ma carte ?'), findsOneWidget);
    expect(
      find.text("Plus aucun paiement ni retrait jusqu'à la réactivation. Vous pourrez la réactiver à tout moment."),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();

    expect(env.db.cardStatus, 'INACTIVE');
    expect(find.text('Carte suspendue.'), findsOneWidget);
    expect(find.text('Suspendue'), findsOneWidget);
    expect(find.byKey(const Key('card-action-reactivate')), findsOneWidget);
    expect(find.byKey(const Key('card-action-suspend')), findsNothing);
    expect(opacityOf(tester, 'card-action-view'), 0.4);

    // Réactivation.
    await tester.tap(find.byKey(const Key('card-action-reactivate')));
    await tester.pumpAndSettle();
    expect(find.text('Réactiver ma carte ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();
    expect(env.db.cardStatus, 'ACTIVE');
    expect(find.text('Carte réactivée.'), findsOneWidget);
    expect(find.byKey(const Key('card-action-suspend')), findsOneWidget);
  });

  testWidgets('annuler le dialogue ne change rien', (tester) async {
    final env = await pump(tester);
    await tester.tap(find.byKey(const Key('card-action-suspend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-cancel')));
    await tester.pumpAndSettle();
    expect(env.db.cardStatus, 'ACTIVE');
    expect(find.byKey(const Key('card-action-suspend')), findsOneWidget);
  });

  testWidgets('déclarer perdue ou volée → bloquée, actions grisées', (tester) async {
    final env = await pump(tester);
    await tester.tap(find.byKey(const Key('card-action-lost')));
    await tester.pumpAndSettle();
    expect(find.text('Déclarer perdue ou volée ?'), findsOneWidget);
    expect(
      find.text(
        'Ce blocage est définitif. Vos fonds ne sont pas perdus : le support pourra les transférer sur une nouvelle carte.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();

    expect(env.db.cardStatus, 'LOST_OR_STOLEN');
    expect(env.db.notifications.first['title'], 'Carte bloquée');
    expect(find.text('Carte bloquée. Une alerte a été envoyée sur tous vos canaux.'), findsOneWidget);
    expect(find.text('Bloquée'), findsOneWidget);
    expect(opacityOf(tester, 'card-action-lost'), 0.4);
    expect(opacityOf(tester, 'card-action-suspend'), 0.4);

    // Nouvelle tentative : simple message, pas de dialogue.
    await tester.tap(find.byKey(const Key('card-action-lost')));
    await tester.pumpAndSettle();
    expect(find.text('Déclarer perdue ou volée ?'), findsNothing);
    expect(
      find.text(
        'Carte déclarée perdue ou volée. Contactez le support : vos fonds peuvent être transférés sur une nouvelle carte.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('carte suspendue : « Voir numéro et CVV » affiche la raison', (tester) async {
    await pump(tester, status: 'INACTIVE');
    await tester.tap(find.byKey(const Key('card-action-view')));
    await tester.pumpAndSettle();
    expect(find.text('Cette carte est suspendue. Réactivez-la pour payer à nouveau.'), findsOneWidget);
  });

  testWidgets('erreur serveur → message affiché, statut inchangé', (tester) async {
    final env = await pump(tester);
    env.db.cardStatus = 'INACTIVE'; // désynchronisé : le serveur refusera la suspension
    await tester.tap(find.byKey(const Key('card-action-suspend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Votre carte est déjà suspendue.'), findsOneWidget);
    expect(find.byKey(const Key('card-action-suspend')), findsOneWidget);
  });
}
