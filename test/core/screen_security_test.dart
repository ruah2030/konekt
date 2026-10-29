import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/security/screen_security.dart';
import 'package:konekt/features/card/presentation/screens/secure_display_screen.dart';

import '../helpers/test_app.dart';

void main() {
  const channel = MethodChannel('konekt/screen_security');

  testWidgets('protection activée sur l’affichage de carte, désactivée en le quittant', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: true));
    await env.pumpScreen(tester, const SecureDisplayScreen());
    expect(calls, contains('enable'));
    await tester.pumpWidget(const SizedBox());
    expect(calls.last, 'disable');
  });

  testWidgets('iOS : une capture d’écran sur l’affichage de carte déclenche un avertissement', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: true));
    await env.pumpScreen(tester, const SecureDisplayScreen());
    await tester.pump();

    // Le côté natif (AppDelegate.swift) signale la capture.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('screenshotTaken')),
      (_) {},
    );
    await tester.pump();
    expect(find.text(SecureDisplayScreenWarning.text), findsOneWidget);
    expect(ScreenSecurity.screenshots, isNotNull);
  });
}
