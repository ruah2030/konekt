import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/auth/presentation/screens/login_screen.dart';
import 'package:konekt/features/auth/presentation/screens/otp_screen.dart';

import '../../helpers/test_app.dart';
import 'router_harness.dart';

/// L'écran du code a un compte à rebours (timer périodique) : pas de `pumpAndSettle`.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<(TestEnv, ProviderContainer)> toOtp(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
    usePhoneSize(tester);
    final env = await TestEnv.create(prefs: prefs);
    final container = await pumpWithRouter(
      tester,
      env,
      initial: Routes.login,
      screens: {Routes.login: LoginScreen.new, Routes.otp: OtpScreen.new},
    );
    container.read(authControllerProvider);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-card-id')), '121436474');
    await tester.enterText(find.byKey(const Key('login-last4')), '4589');
    await tester.tap(find.byKey(const Key('login-submit')));
    await settle(tester);
    return (env, container);
  }

  Future<void> typeCode(WidgetTester tester, String code) async {
    for (final d in code.split('')) {
      await tester.tap(find.byKey(Key('key-$d')));
      await tester.pump();
    }
    await settle(tester);
  }

  testWidgets('destination masquée et compte à rebours', (tester) async {
    await toOtp(tester);
    expect(find.text('Saisissez le code reçu'), findsOneWidget);
    final subtitle = tester.widget<Text>(find.byKey(const Key('code-subtitle'))).data!;
    expect(subtitle, matches(RegExp(r'^Envoyé au \+229\*{4}456 par SMS\. Expire dans [45]:[0-5]\d$')));
  });

  testWidgets('succès → session ouverte avec la carte, code d’invitation transmis', (tester) async {
    final (env, container) = await toOtp(tester, prefs: {'merchant_referral_code': 'REF-XYZ123'});
    await typeCode(tester, '482910');
    final auth = container.read(authControllerProvider);
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.session?.cardCustomerId, '121436474');
    expect(auth.session?.last4, '4589');
    expect(auth.hasPin, isFalse);
    expect(container.read(loginChallengeProvider), isNull);
    expect(await env.store.sessionToken, isNotNull);
    expect(env.prefs.referralCode, 'REF-XYZ123');
  });

  testWidgets('401 → message du serveur et saisie vidée', (tester) async {
    final (_, container) = await toOtp(tester);
    await typeCode(tester, '000000');
    expect(find.text('Code incorrect. 2 essai(s) restant(s).'), findsOneWidget);
    expect(container.read(authControllerProvider).isAuthenticated, isFalse);
    final dot = tester.widget<Text>(
      find.descendant(of: find.byKey(const Key('pin-dot-0')), matching: find.byType(Text)),
    );
    expect(dot.data, isNot('0'));
  });

  testWidgets('403 carte perdue → message + « Contacter le support »', (tester) async {
    final (env, _) = await toOtp(tester);
    env.db.cardStatus = 'LostOrStolen';
    await typeCode(tester, '482910');
    expect(find.textContaining('déclarée perdue ou volée'), findsOneWidget);
    expect(find.text('Contacter le support'), findsOneWidget);
    await tester.tap(find.text('Contacter le support'));
    await tester.pump();
    expect(find.text(OtpScreen.supportMessage), findsOneWidget);
  });

  testWidgets('renvoyer un code : nouveau login/init, puis limite horaire du serveur', (tester) async {
    final (env, _) = await toOtp(tester);
    expect(env.db.loginCodesThisHour, 1);
    await tester.tap(find.text('Renvoyer un code'));
    await settle(tester);
    expect(find.text('Nouveau code envoyé.'), findsOneWidget);
    expect(env.db.loginCodesThisHour, 2);

    env.db.loginCodesThisHour = 3;
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('Renvoyer un code'));
    await settle(tester);
    expect(find.text('Trop de demandes de code. Réessayez dans une heure.'), findsOneWidget);
  });
}
