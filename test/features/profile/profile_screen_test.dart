import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/profile/presentation/screens/profile_screen.dart';

import '../../helpers/test_app.dart';

/// Hors routeur, l'écran reste monté après la déconnexion : on avance de quelques frames.
Future<void> settleAfterLogout(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<(TestEnv, ProviderContainer)> pump(WidgetTester tester, {FakeDb? db}) async {
    tester.view
      ..physicalSize = const Size(1200, 3200)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = await TestEnv.create(signedIn: true, db: db ?? FakeDb(hasPin: true));
    await env.pumpScreen(tester, const ProfileScreen());
    final container = ProviderScope.containerOf(tester.element(find.byType(ProfileScreen)));
    await tester.pumpAndSettle();
    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
    return (env, container);
  }

  testWidgets('en-tête issu de la session, sécurité et préférence courante', (tester) async {
    await pump(tester);
    expect(find.text('Awa Houngbédji'), findsOneWidget);
    expect(find.text('AH'), findsOneWidget);
    expect(find.text('Carte •••• 4589'), findsOneWidget);
    expect(find.text('Changer mon code secret'), findsOneWidget);
    expect(find.text('Code secret oublié'), findsOneWidget);
    expect(find.text('Appareils connectés'), findsOneWidget);
    expect(find.text('2 appareil(s) connecté(s)'), findsOneWidget);
    expect(find.byKey(const Key('channel-sms')), findsOneWidget);
  });

  testWidgets('choisir un canal → PATCH preferences ; Auto → null', (tester) async {
    final (env, _) = await pump(tester);
    await tester.tap(find.byKey(const Key('channel-email')));
    await tester.pumpAndSettle();
    expect(env.db.preferredChannel, 'EMAIL');
    expect(find.text('Préférence enregistrée.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('channel-auto')));
    await tester.pumpAndSettle();
    expect(env.db.preferredChannel, isNull);
  });

  testWidgets('carte externe : 409 affiché', (tester) async {
    final (env, _) = await pump(tester, db: FakeDb(hasPin: true)..isExternalCard = true);
    await tester.tap(find.byKey(const Key('channel-whatsapp')));
    await tester.pumpAndSettle();
    expect(find.textContaining('aucune préférence de canal'), findsOneWidget);
    expect(env.db.preferredChannel, 'SMS');
  });

  testWidgets('se déconnecter → session fermée côté serveur et localement', (tester) async {
    final (env, container) = await pump(tester);
    final token = await env.store.sessionToken;
    await tester.tap(find.byKey(const Key('profile-logout')));
    await settleAfterLogout(tester);
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(env.db.isValidSessionToken(token), isFalse);
  });

  testWidgets('déconnecter tous les appareils → toast « N sessions fermées. »', (tester) async {
    final (_, container) = await pump(tester);
    await tester.tap(find.byKey(const Key('profile-logout-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settleAfterLogout(tester);
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(find.text('2 sessions fermées.'), findsOneWidget);
  });
}
