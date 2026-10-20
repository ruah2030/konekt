import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/profile/presentation/screens/devices_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  Future<(TestEnv, ProviderContainer)> pump(WidgetTester tester) async {
    final env = await TestEnv.create(signedIn: true);
    await env.pumpScreen(tester, const DevicesScreen());
    final container = ProviderScope.containerOf(tester.element(find.byType(DevicesScreen)));
    container.read(authControllerProvider); // session restaurée, comme dans l'app
    await tester.pumpAndSettle();
    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
    return (env, container);
  }

  testWidgets('liste des appareils', (tester) async {
    await pump(tester);
    expect(find.text('Appareils connectés'), findsOneWidget);
    expect(find.text('Cet appareil'), findsNWidgets(2)); // libellé + badge
    expect(find.text('Android · actif maintenant'), findsOneWidget);
    expect(find.text('iPhone 12'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^iOS · vu \d+ [a-zéû.]+ à \d\d:\d\d$')), findsOneWidget);
    expect(find.text('Navigateur web'), findsOneWidget);
    expect(find.text('Déconnecter'), findsNWidgets(3));
  });

  testWidgets('déconnecter un appareil non courant', (tester) async {
    final (env, container) = await pump(tester);
    await tester.tap(find.byKey(const Key('device-disconnect-dv2')));
    await tester.pumpAndSettle();
    expect(find.text('Déconnecter « iPhone 12 » ?'), findsOneWidget);
    expect(find.text('La session de cet appareil est fermée immédiatement.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();

    expect(find.text('Appareil déconnecté.'), findsOneWidget);
    expect(find.text('iPhone 12'), findsNothing);
    expect(env.db.devices.map((d) => d['id']), isNot(contains('dv2')));
    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
  });

  testWidgets('déconnecter cet appareil → fin de session', (tester) async {
    final (env, container) = await pump(tester);
    await tester.tap(find.byKey(const Key('device-disconnect-dv_current')));
    await tester.pumpAndSettle();
    expect(find.text('C’est l’appareil que vous utilisez : vous reviendrez à l’écran de connexion.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(env.db.accessTokens, isEmpty);
    expect(await env.store.accessToken, isNull);
  });
}
