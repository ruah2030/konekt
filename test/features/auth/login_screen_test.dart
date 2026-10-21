import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/core/storage/app_prefs.dart';
import 'package:konekt/core/storage/secure_store.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
import 'package:konekt/features/auth/data/auth_repository.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/auth/presentation/providers/login_controller.dart';
import 'package:konekt/features/auth/presentation/screens/login_screen.dart';

import '../../helpers/test_app.dart';
import 'router_harness.dart';

/// `login/init` qui échoue toujours avec [failure].
class _FailingAuthRepo extends AuthRepository {
  _FailingAuthRepo(super.dio, super.store, super.prefs, this.failure);
  final ApiFailure failure;

  @override
  Future<LoginChallenge> loginInit({required String cardId, required String last4, OtpChannel? channel}) =>
      Future.error(failure);
}

void main() {
  Future<void> fill(WidgetTester tester, {String cardId = '121436474', String last4 = '4589'}) async {
    await tester.enterText(find.byKey(const Key('login-card-id')), cardId);
    await tester.enterText(find.byKey(const Key('login-last4')), last4);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
  }

  Future<(TestEnv, ProviderContainer)> pumpLogin(WidgetTester tester, {TestEnv? env}) async {
    usePhoneSize(tester);
    final e = env ?? await TestEnv.create();
    final c = await pumpWithRouter(
      tester,
      e,
      initial: Routes.login,
      screens: {Routes.login: LoginScreen.new, Routes.otp: () => routeStub(Routes.otp)},
    );
    await tester.pumpAndSettle();
    return (e, c);
  }

  /// Écran de connexion avec un dépôt dont `login/init` renvoie [failure].
  Future<void> pumpWithFailure(WidgetTester tester, ApiFailure failure) async {
    usePhoneSize(tester);
    final env = await TestEnv.create();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          authRepositoryProvider.overrideWith(
            (ref) => _FailingAuthRepo(
              ref.watch(dioProvider),
              ref.watch(secureStoreProvider),
              ref.watch(appPrefsProvider),
              failure,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(useGoogleFonts: false),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SegmentedButton<OtpChannel> channels(WidgetTester tester) =>
      tester.widget<SegmentedButton<OtpChannel>>(find.byKey(const Key('login-channel')));

  testWidgets('canaux : indisponibles grisés avec mention, défaut présélectionné', (tester) async {
    await pumpLogin(tester);
    final seg = channels(tester);
    expect(seg.selected, {OtpChannel.sms});
    expect(seg.segments.firstWhere((s) => s.value == OtpChannel.whatsapp).enabled, isFalse);
    expect(seg.segments.firstWhere((s) => s.value == OtpChannel.email).enabled, isTrue);
    expect(find.text('WhatsApp momentanément indisponible'), findsOneWidget);
    expect(find.text('SMS momentanément indisponible'), findsNothing);
  });

  testWidgets('canaux : SMS en panne → e-mail présélectionné', (tester) async {
    final env = await TestEnv.create();
    env.db.channels['SMS'] = false;
    await pumpLogin(tester, env: env);
    expect(channels(tester).selected, {OtpChannel.email});
    expect(find.text('SMS momentanément indisponible'), findsOneWidget);
  });

  testWidgets('validations locales sous les champs', (tester) async {
    await pumpLogin(tester);
    await fill(tester, cardId: '12O436474', last4: '45');
    expect(find.text(LoginController.letterOMessage), findsOneWidget);
    expect(find.text(LoginController.last4Message), findsOneWidget);

    await fill(tester, cardId: '12345', last4: '4589');
    expect(find.text(LoginController.cardIdMessage), findsOneWidget);
    expect(find.text(LoginController.last4Message), findsNothing);
  });

  testWidgets('401 → message volontairement vague', (tester) async {
    await pumpLogin(tester);
    await fill(tester, last4: '0000');
    expect(find.text(LoginController.invalidCredentialsMessage), findsOneWidget);
  });

  testWidgets('400 → message du serveur (3 codes par heure)', (tester) async {
    final env = await TestEnv.create();
    env.db.loginCodesThisHour = 3;
    await pumpLogin(tester, env: env);
    await fill(tester);
    expect(find.text('Trop de demandes de code. Réessayez dans une heure.'), findsOneWidget);
  });

  testWidgets('VALIDATION_FAILED → details sous les champs', (tester) async {
    await pumpWithFailure(
      tester,
      const ApiFailure(
        code: ErrorCodes.validationFailed,
        message: 'Certains champs sont invalides.',
        statusCode: 400,
        details: {
          'cardCustomerId': ['Identifiant refusé par le serveur.'],
          'last4Digits': ['Quatre chiffres attendus (serveur).'],
        },
      ),
    );
    await fill(tester);
    expect(find.text('Identifiant refusé par le serveur.'), findsOneWidget);
    expect(find.text('Quatre chiffres attendus (serveur).'), findsOneWidget);
    expect(find.byKey(const Key('error-block')), findsNothing);
  });

  testWidgets('429 → « Patientez une minute. »', (tester) async {
    await pumpWithFailure(
      tester,
      const ApiFailure(code: ErrorCodes.rateLimited, message: 'Too many requests', statusCode: 429),
    );
    await fill(tester);
    expect(find.text(LoginController.tooManyCallsMessage), findsOneWidget);
  });

  testWidgets('succès → défi enregistré et écran du code', (tester) async {
    final (env, c) = await pumpLogin(tester);
    await tester.tap(find.byKey(const Key('channel-EMAIL')));
    await tester.pump();
    await fill(tester, cardId: '121 436 474');
    expect(find.text('route:${Routes.otp}'), findsOneWidget);
    final challenge = c.read(loginChallengeProvider)!;
    expect(challenge.cardCustomerId, '121436474');
    expect(challenge.last4Digits, '4589');
    expect(challenge.channelsUsed, [OtpChannel.email]);
    expect(challenge.maskedContacts, [env.db.maskedEmail]);
  });
}
