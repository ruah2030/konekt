import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/security/device_auth.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
import 'package:konekt/features/card/presentation/screens/card_screen.dart';

import '../../helpers/test_app.dart';

/// Déverrouillage du téléphone simulé.
class _FakeDeviceAuth implements DeviceAuth {
  _FakeDeviceAuth(this.result);
  final DeviceAuthResult result;
  final reasons = <String>[];

  @override
  Future<DeviceAuthResult> confirm(String reason) async {
    reasons.add(reason);
    return result;
  }
}

void main() {
  Future<TestEnv> pump(WidgetTester tester, _FakeDeviceAuth auth) async {
    tester.view
      ..physicalSize = const Size(1200, 3200)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: true))
      ..deviceAuth = auth;
    await tester.pumpWidget(
      ProviderScope(
        overrides: env.overrides,
        child: MaterialApp(
          theme: AppTheme.light(useGoogleFonts: false),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const CardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return env;
  }

  Future<void> suspend(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('card-action-suspend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();
  }

  testWidgets('déverrouillage refusé : rien n’est envoyé, la carte reste active', (tester) async {
    final auth = _FakeDeviceAuth(DeviceAuthResult.refused);
    final env = await pump(tester, auth);
    await suspend(tester);
    expect(auth.reasons.single, contains('suspension'));
    expect(env.db.cardStatus, 'Active');
    expect(find.text(deviceAuthRefusedMessage), findsOneWidget);
    expect(find.byKey(const Key('card-action-suspend')), findsOneWidget);
  });

  testWidgets('déverrouillage validé : la carte est suspendue', (tester) async {
    final env = await pump(tester, _FakeDeviceAuth(DeviceAuthResult.authenticated));
    await suspend(tester);
    expect(env.db.cardStatus, 'Inactive');
    expect(find.byKey(const Key('card-action-reactivate')), findsOneWidget);
  });

  testWidgets('téléphone sans verrouillage : la confirmation suffit (impossible de vérifier)', (tester) async {
    final env = await pump(tester, _FakeDeviceAuth(DeviceAuthResult.unavailable));
    await suspend(tester);
    expect(env.db.cardStatus, 'Inactive');
  });
}
