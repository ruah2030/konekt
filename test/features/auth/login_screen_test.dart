import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/auth/presentation/screens/login_screen.dart';

import '../../helpers/test_app.dart';
import 'router_harness.dart';

void main() {
  Future<(TestEnv, ProviderContainer)> pumpLogin(WidgetTester tester, {FakeDb? db}) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(db: db);
    final container = await pumpWithRouter(
      tester,
      env,
      initial: Routes.login,
      screens: {Routes.login: LoginScreen.new, Routes.otp: () => routeStub(Routes.otp)},
    );
    await tester.pumpAndSettle();
    return (env, container);
  }

  Future<void> fill(WidgetTester tester, String cardId, String last4) async {
    await tester.enterText(find.byKey(const Key('login-card-id')), cardId);
    await tester.enterText(find.byKey(const Key('login-last4')), last4);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('affiche le formulaire et WhatsApp indisponible', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Connectez votre carte'), findsOneWidget);
    expect(find.text('Recevoir mon code'), findsOneWidget);
    expect(find.text('WhatsApp momentanément indisponible'), findsOneWidget);
    expect(find.text('Une session par carte. Pour une autre carte, reconnectez-vous avec elle.'), findsOneWidget);
    expect(find.byKey(const Key('incident-banner')), findsNothing);
  });

  testWidgets('bannière incident', (tester) async {
    await pumpLogin(tester, db: FakeDb(incident: true));
    expect(find.byKey(const Key('incident-banner')), findsOneWidget);
  });

  testWidgets('validations locales avec messages exacts', (tester) async {
    await pumpLogin(tester);
    await fill(tester, '12O456789', '4589');
    expect(
      find.text('Chiffres uniquement : vérifiez qu’aucune lettre « O » n’a été saisie à la place du zéro.'),
      findsOneWidget,
    );
    expect(find.textContaining('REQUEST_REJECTED'), findsOneWidget);

    await fill(tester, '12345', '4589');
    expect(find.text("L'identifiant de carte compte 6 à 20 chiffres."), findsOneWidget);

    await fill(tester, '121436474', '45');
    expect(find.text('Quatre chiffres attendus.'), findsOneWidget);
  });

  testWidgets('erreur serveur affichée avec code et référence', (tester) async {
    await pumpLogin(tester);
    await fill(tester, '121436474', '0000');
    expect(find.text('Identifiant ou chiffres incorrects.'), findsOneWidget);
    expect(find.textContaining('UNAUTHENTICATED · Réf. req_'), findsOneWidget);
  });

  testWidgets('succès → défi enregistré et navigation vers l’OTP', (tester) async {
    final (_, container) = await pumpLogin(tester);
    await tester.tap(find.text('E-mail'));
    await tester.pumpAndSettle();
    await fill(tester, '121 436 474', '4589');
    expect(find.text('route:${Routes.otp}'), findsOneWidget);
    final c = container.read(loginChallengeProvider);
    expect(c, isNotNull);
    expect(c!.channel, OtpChannel.email);
  });
}
