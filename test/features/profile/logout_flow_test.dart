import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_db.dart';

import '../../helpers/test_app.dart';

/// Parcours réel (routeur de l'app) : la déconnexion ramène à l'écran de connexion.
void main() {
  Future<TestEnv> openProfile(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: true), prefs: {'first_launch_done': true});
    await env.pumpApp(tester);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('tab-Profil')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return env;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('« Se déconnecter » ferme la session et ouvre l’écran de connexion', (tester) async {
    final env = await openProfile(tester);
    await tester.ensureVisible(find.byKey(const Key('profile-logout')));
    await tester.tap(find.byKey(const Key('profile-logout')));
    await settle(tester);
    expect(find.byKey(const Key('login-card-id')), findsOneWidget);
    expect(await env.store.sessionToken, isNull);
  });

  testWidgets('« Déconnecter tous mes appareils » ferme la session et ouvre l’écran de connexion', (tester) async {
    final env = await openProfile(tester);
    await tester.ensureVisible(find.byKey(const Key('profile-logout-all')));
    await tester.tap(find.byKey(const Key('profile-logout-all')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);
    expect(find.byKey(const Key('login-card-id')), findsOneWidget);
    expect(await env.store.sessionToken, isNull);
  });
}
