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

void main() {
  Future<(TestEnv, ProviderContainer)> toOtp(WidgetTester tester) async {
    usePhoneSize(tester);
    final env = await TestEnv.create();
    final container = await pumpWithRouter(
      tester,
      env,
      initial: Routes.login,
      screens: {Routes.login: LoginScreen.new, Routes.otp: OtpScreen.new},
    );
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

  testWidgets('affiche la destination masquée et le compte à rebours', (tester) async {
    await toOtp(tester);
    expect(find.text('Saisissez le code reçu'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Envoyé au \+229 •• •• •• 456 par SMS\. Expire dans [45]:\d\d\.$')),
      findsOneWidget,
    );
    expect(find.text('Renvoyer un code'), findsOneWidget);
  });

  testWidgets('code correct → session ouverte', (tester) async {
    final (env, container) = await toOtp(tester);
    await typeCode(tester, '123456');
    final auth = container.read(authControllerProvider);
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.hasPin, isFalse);
    expect(container.read(loginChallengeProvider), isNull);
    expect(env.store.accessToken, completion(isNotNull));
  });

  testWidgets('000000 → erreur, saisie vidée', (tester) async {
    final (_, container) = await toOtp(tester);
    await typeCode(tester, '000000');
    expect(find.text('Code incorrect. 2 essai(s) restant(s).'), findsOneWidget);
    expect(find.textContaining('UNAUTHENTICATED'), findsOneWidget);
    expect(find.text('0'), findsOneWidget); // seulement la touche du pavé, les cases sont vides
    expect(container.read(authControllerProvider).isAuthenticated, isFalse);
  });

  testWidgets('renvoi du code puis limite atteinte', (tester) async {
    await toOtp(tester);
    await tester.tap(find.byKey(const Key('code-link')));
    await settle(tester);
    expect(find.text('Nouveau code envoyé.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('code-link')));
    await settle(tester);
    expect(find.text('Limite de 3 codes par heure atteinte'), findsOneWidget);
    final link = tester.widget<TextButton>(find.byKey(const Key('code-link')));
    expect(link.onPressed, isNull);
  });

  testWidgets('retour → écran de connexion', (tester) async {
    await toOtp(tester);
    await tester.tap(find.byKey(const Key('code-back')));
    await settle(tester);
    expect(find.text('Connectez votre carte'), findsOneWidget);
  });
}

/// L'horloge (nowProvider) tourne en continu : pas de pumpAndSettle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}
