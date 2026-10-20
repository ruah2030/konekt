import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/features/pin/presentation/screens/pin_flow_screen.dart';

import '../../helpers/test_app.dart';
import 'router_harness.dart';

void main() {
  testWidgets('app complète : splash → connexion → OTP → création du code secret', (tester) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(prefs: {'first_launch_done': true});
    await env.pumpApp(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Connectez votre carte'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-card-id')), '121436474');
    await tester.enterText(find.byKey(const Key('login-last4')), '4589');
    await tester.tap(find.byKey(const Key('login-submit')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Saisissez le code reçu'), findsOneWidget);

    for (final d in '123456'.split('')) {
      await tester.tap(find.byKey(Key('key-$d')));
      await tester.pump();
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PinFlowScreen), findsOneWidget);
    expect(find.text('Sécurisons votre compte'), findsOneWidget);
    expect(find.text('Étape 1 sur 3'), findsOneWidget);
  });
}
