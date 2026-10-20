import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/pin/domain/pin_flow.dart';
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

  testWidgets('setup : 3 étapes, PIN masqué, création et toast', (tester) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(signedIn: true);
    final container = await pumpWithRouter(
      tester,
      env,
      initial: Routes.pinSetup,
      screens: {Routes.pinSetup: () => const PinFlowScreen(flow: PinFlow.setup)},
    );
    await tester.pumpAndSettle();

    expect(find.text('Sécurisons votre compte'), findsOneWidget);
    expect(find.text('Étape 1 sur 3'), findsOneWidget);
    expect(find.byKey(const Key('code-back')), findsNothing);

    // Code de vérification affiché en clair.
    await tester.tap(find.byKey(const Key('key-7')));
    await tester.pump();
    expect(dot(tester, 0), '7');
    await typeCode(tester, '12345');

    expect(find.text('Choisissez votre code secret'), findsOneWidget);
    expect(find.text('Étape 2 sur 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('key-4')));
    await tester.pump();
    expect(dot(tester, 0), '●');
    await typeCode(tester, '82915');

    expect(find.text('Confirmez votre code secret'), findsOneWidget);
    expect(find.text('Étape 3 sur 3'), findsOneWidget);
    expect(find.byKey(const Key('code-back')), findsOneWidget);
    await typeCode(tester, '482915');

    expect(find.text('Code secret créé. Il confirmera chacun de vos paiements.'), findsOneWidget);
    expect(container.read(authControllerProvider).hasPin, isTrue);
    expect(env.db.pin, '482915');
  });

  testWidgets('setup : PIN faible puis confirmation différente', (tester) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(signedIn: true);
    await env.pumpScreen(tester, const PinFlowScreen(flow: PinFlow.setup));
    await tester.pumpAndSettle();
    await typeCode(tester, '123456');

    await typeCode(tester, '111111');
    expect(find.text('Code trop simple : évitez les chiffres identiques et les suites.'), findsOneWidget);
    expect(find.textContaining('PIN_TOO_WEAK'), findsOneWidget);

    await typeCode(tester, '482915');
    await typeCode(tester, '482910');
    expect(find.text('Choisissez votre code secret'), findsOneWidget);
    expect(find.text('Les deux codes ne correspondent pas. Recommencez.'), findsOneWidget);
  });

  testWidgets('change : ancien → nouveau → confirmation → profil', (tester) async {
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
    expect(find.text('Code secret incorrect. 4 essai(s) avant verrouillage.'), findsOneWidget);

    await typeCode(tester, '482915');
    expect(find.text('Nouveau code secret'), findsOneWidget);
    await typeCode(tester, '135790');
    await typeCode(tester, '135790');

    expect(find.text('route:${Routes.profile}'), findsOneWidget);
    expect(find.text('Code secret modifié.'), findsOneWidget);
    expect(env.db.pin, '135790');
  });

  testWidgets('reset : titre « Code secret oublié », retour vers le profil', (tester) async {
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
    await typeCode(tester, '000000');
    expect(find.text('Code incorrect, 2 essai(s) restant(s).'), findsOneWidget);

    await tester.tap(find.byKey(const Key('code-back')));
    await tester.pumpAndSettle();
    expect(find.text('route:${Routes.profile}'), findsOneWidget);
  });
}
