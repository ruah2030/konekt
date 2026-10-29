import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_db.dart';

import '../../helpers/test_app.dart';

void main() {
  testWidgets('carte bloquée pendant la session : écran de connexion avec motif et accès au support', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: true), prefs: {'first_launch_done': true});
    await env.pumpApp(tester);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // La carte est bloquée et la session doit être renouvelée : le refresh répond 403.
    env.db
      ..cardStatus = 'Deactivated'
      ..revokeSessionToken(await env.store.sessionToken);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400)); // tirer pour rafraîchir
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('login-session-ended')), findsOneWidget);
    expect(find.textContaining('désactivée'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-contact-support')));
    await tester.pump();
    expect(find.textContaining('Support Konekt'), findsOneWidget);
  });
}
