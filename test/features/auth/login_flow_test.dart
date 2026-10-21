import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/features/home/presentation/screens/home_screen.dart';
import 'package:konekt/features/pin/presentation/screens/pin_flow_screen.dart';

import '../../helpers/test_app.dart';
import 'router_harness.dart';

void main() {
  Future<void> pumps(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> typeCode(WidgetTester tester, String code) async {
    for (final d in code.split('')) {
      await tester.tap(find.byKey(Key('key-$d')));
      await tester.pump();
    }
    await pumps(tester);
  }

  testWidgets('app complète : splash → connexion → code → création du PIN → accueil', (tester) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(prefs: {'first_launch_done': true, 'merchant_referral_code': 'REF-XYZ123'});
    await env.pumpApp(tester);
    await tester.pump(const Duration(seconds: 3));
    await pumps(tester);
    expect(find.text('Connectez votre carte'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-card-id')), '121436474');
    await tester.enterText(find.byKey(const Key('login-last4')), '4589');
    await tester.tap(find.byKey(const Key('login-submit')));
    await pumps(tester);
    expect(find.text('Saisissez le code reçu'), findsOneWidget);

    await typeCode(tester, '482910');
    expect(find.byType(PinFlowScreen), findsOneWidget);
    expect(find.text('Sécurisons votre compte'), findsOneWidget);
    expect(find.text('Étape 1 sur 3'), findsOneWidget);
    expect(env.db.pinCode?['purpose'], 'setup');

    await typeCode(tester, '604218');
    expect(find.text('Choisissez votre code secret'), findsOneWidget);
    await typeCode(tester, '482915');
    expect(find.text('Confirmez votre code secret'), findsOneWidget);
    await typeCode(tester, '482915');
    await pumps(tester, 20);

    expect(env.db.pin, '482915');
    expect(find.byType(PinFlowScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect((await env.store.cardSession)?.hasPin, isTrue);
  });
}
