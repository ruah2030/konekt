import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/profile/presentation/screens/devices_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  Future<(TestEnv, ProviderContainer)> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 3200)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = await TestEnv.create(signedIn: true);
    await env.pumpScreen(tester, const DevicesScreen());
    final container = ProviderScope.containerOf(tester.element(find.byType(DevicesScreen)));
    container.read(authControllerProvider);
    await tester.pumpAndSettle();
    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
    return (env, container);
  }

  testWidgets('liste : « Cet appareil », sessions actives seulement déconnectables', (tester) async {
    await pump(tester);
    expect(find.text('Appareils connectés'), findsOneWidget);
    expect(find.byKey(const Key('device-current-badge')), findsOneWidget);
    expect(find.textContaining('Android · actif maintenant'), findsOneWidget);
    expect(find.text('iPhone 12'), findsOneWidget);
    expect(find.text('Navigateur web'), findsOneWidget);
    expect(find.text('Déconnecter'), findsNWidgets(2));
    expect(find.byKey(const Key('device-disconnect-cldev_web')), findsNothing);
  });

  testWidgets('déconnecter un appareil non courant', (tester) async {
    final (env, container) = await pump(tester);
    await tester.tap(find.byKey(const Key('device-disconnect-cldev_iphone')));
    await tester.pumpAndSettle();
    expect(find.text('Déconnecter « iPhone 12 » ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();

    expect(find.text('Appareil déconnecté.'), findsOneWidget);
    expect(find.byKey(const Key('device-disconnect-cldev_iphone')), findsNothing);
    expect(env.db.devices.firstWhere((d) => d['deviceId'] == 'cldev_iphone')['hasActiveSession'], isFalse);
    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
  });

  testWidgets('déconnecter cet appareil → confirmation puis fin de session', (tester) async {
    final (env, container) = await pump(tester);
    final token = await env.store.sessionToken;
    await tester.tap(find.byKey(const Key('device-disconnect-cldev_current')));
    await tester.pumpAndSettle();
    expect(find.text('Déconnecter cet appareil ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(env.db.isValidSessionToken(token), isFalse);
    expect(await env.store.sessionToken, isNull);
  });

  testWidgets('annuler : rien ne change', (tester) async {
    final (env, _) = await pump(tester);
    await tester.tap(find.byKey(const Key('device-disconnect-cldev_current')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-cancel')));
    await tester.pumpAndSettle();
    expect(env.db.devices.first['hasActiveSession'], isTrue);
  });
}
