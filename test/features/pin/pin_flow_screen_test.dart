import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/pin/domain/pin_flow.dart';
import 'package:konekt/features/pin/domain/pin_rules.dart';
import 'package:konekt/features/pin/presentation/screens/pin_flow_screen.dart';

import '../../helpers/test_app.dart';
import '../auth/router_harness.dart';

void main() {
  Future<void> typeCode(WidgetTester tester, String code) async {
    for (final d in code.split('')) {
      await tester.tap(find.byKey(Key('key-$d')));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  String dot(WidgetTester tester, int i) =>
      tester.widget<Text>(find.descendant(of: find.byKey(Key('pin-dot-$i')), matching: find.byType(Text))).data!;

  testWidgets('création : 3 étapes, contacts masqués, PIN masqué, toast', (tester) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(signedIn: true);
    final container = await pumpWithRouter(
      tester,
      env,
      initial: Routes.pinSetup,
      screens: {Routes.pinSetup: () => const PinFlowScreen(flow: PinFlow.setup)},
    );
    container.read(authControllerProvider);
    await tester.pumpAndSettle();

    expect(find.text('Sécurisons votre compte'), findsOneWidget);
    expect(find.text('Étape 1 sur 3'), findsOneWidget);
    expect(
      find.text('Saisissez le code envoyé au ${env.db.maskedPhone} et ${env.db.maskedEmail}. Valable 5 minutes.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('code-back')), findsNothing);

    // Code de vérification affiché en clair.
    await tester.tap(find.byKey(const Key('key-6')));
    await tester.pump();
    expect(dot(tester, 0), '6');
    await typeCode(tester, '04218');

    expect(find.text('Choisissez votre code secret'), findsOneWidget);
    expect(find.text('Étape 2 sur 3'), findsOneWidget);
    await typeCode(tester, '987654');
    expect(find.text(PinRules.sequenceMessage), findsOneWidget);

    await tester.tap(find.byKey(const Key('key-4')));
    await tester.pump();
    expect(dot(tester, 0), '●');
    await typeCode(tester, '82915');

    expect(find.text('Confirmez votre code secret'), findsOneWidget);
    expect(find.text('Étape 3 sur 3'), findsOneWidget);
    await typeCode(tester, '482915');

    expect(find.text(PinFlowScreen.createdMessage), findsOneWidget);
    expect(container.read(authControllerProvider).hasPin, isTrue);
    expect(env.db.pin, '482915');
  });

  testWidgets('création : code faux → étape code avec essais restants', (tester) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(signedIn: true);
    await env.pumpScreen(tester, const PinFlowScreen(flow: PinFlow.setup));
    await tester.pumpAndSettle();
    await typeCode(tester, '000000');
    await typeCode(tester, '482915');
    await typeCode(tester, '482915');
    expect(find.text('Sécurisons votre compte'), findsOneWidget);
    expect(find.text('Code incorrect, 2 essai(s) restant(s).'), findsOneWidget);
  });

  testWidgets('changement : ancien faux (403) → PIN actuel, puis succès → profil', (tester) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: true));
    await pumpWithRouter(
      tester,
      env,
      initial: Routes.pinChange,
      screens: {
        Routes.pinChange: () => const PinFlowScreen(flow: PinFlow.change),
        Routes.profile: () => routeStub(Routes.profile),
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Code secret actuel'), findsOneWidget);
    expect(find.byKey(const Key('code-step')), findsNothing);

    await typeCode(tester, '111222');
    expect(find.text('Nouveau code secret'), findsOneWidget);
    await typeCode(tester, '135790');
    await typeCode(tester, '135790');
    expect(find.text('Code secret actuel'), findsOneWidget);
    expect(find.text('Code secret incorrect — 4 tentative(s) restante(s).'), findsOneWidget);

    await typeCode(tester, '482915');
    await typeCode(tester, '135790');
    await typeCode(tester, '135790');
    expect(find.text('route:${Routes.profile}'), findsOneWidget);
    expect(find.text(PinFlowScreen.changedMessage), findsOneWidget);
    expect(env.db.pin, '135790');
  });

  testWidgets('oubli : titre, code faux, retour vers le profil', (tester) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: true));
    await pumpWithRouter(
      tester,
      env,
      initial: Routes.pinReset,
      screens: {
        Routes.pinReset: () => const PinFlowScreen(flow: PinFlow.reset),
        Routes.profile: () => routeStub(Routes.profile),
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Code secret oublié'), findsOneWidget);
    expect(find.text('Renvoyer un code'), findsOneWidget);

    await tester.tap(find.byKey(const Key('code-back')));
    await tester.pumpAndSettle();
    expect(find.text('route:${Routes.profile}'), findsOneWidget);
  });
}
