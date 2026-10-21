import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/onboarding/presentation/providers/invite_controller.dart';
import 'package:konekt/features/onboarding/presentation/providers/waitlist_controller.dart';
import 'package:konekt/features/onboarding/presentation/screens/invite_screen.dart';
import 'package:konekt/features/onboarding/presentation/screens/request_invite_screen.dart';
import 'package:konekt/features/onboarding/presentation/screens/splash_screen.dart';

import '../../helpers/test_app.dart';
import '../auth/router_harness.dart';

void main() {
  group('Splash', () {
    Future<void> runSplash(WidgetTester tester, TestEnv env) async {
      usePhoneSize(tester);
      await pumpWithRouter(
        tester,
        env,
        initial: Routes.splash,
        screens: {
          Routes.splash: SplashScreen.new,
          Routes.invite: () => routeStub(Routes.invite),
          Routes.login: () => routeStub(Routes.login),
          Routes.home: () => routeStub(Routes.home),
        },
      );
      expect(find.text('POWERED BY BESTCASH'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }

    testWidgets('premier lancement → invitation', (tester) async {
      await runSplash(tester, await TestEnv.create());
      expect(find.text('route:${Routes.invite}'), findsOneWidget);
    });

    testWidgets('lancement suivant → connexion', (tester) async {
      await runSplash(tester, await TestEnv.create(prefs: {'first_launch_done': true}));
      expect(find.text('route:${Routes.login}'), findsOneWidget);
    });

    testWidgets('session valide → accueil', (tester) async {
      await runSplash(tester, await TestEnv.create(signedIn: true, db: FakeDb(hasPin: true)));
      expect(find.text('route:${Routes.home}'), findsOneWidget);
    });
  });

  group('Invitation', () {
    Future<TestEnv> pumpInvite(WidgetTester tester) async {
      usePhoneSize(tester);
      final env = await TestEnv.create();
      await pumpWithRouter(
        tester,
        env,
        initial: Routes.invite,
        screens: {
          Routes.invite: InviteScreen.new,
          Routes.login: () => routeStub(Routes.login),
          Routes.requestInvite: () => routeStub(Routes.requestInvite),
        },
      );
      await tester.pumpAndSettle();
      return env;
    }

    FilledButton submitButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const Key('invite-submit')));

    testWidgets('saisie normalisée, bouton actif à partir de 4 caractères', (tester) async {
      await pumpInvite(tester);
      expect(find.byKey(const Key('invite-video-fallback')), findsOneWidget);
      expect(find.text('SUR INVITATION'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('invite-code')), 'ab1');
      await tester.pump();
      expect(find.text('AB1'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('invite-code')), 'ref-xyz 123!');
      await tester.pump();
      expect(find.text('REF-XYZ123'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('format invalide → message local, aucun enregistrement', (tester) async {
      final env = await pumpInvite(tester);
      await tester.enterText(find.byKey(const Key('invite-code')), '-ABC');
      await tester.pump();
      await tester.tap(find.byKey(const Key('invite-submit')));
      await tester.pumpAndSettle();
      expect(find.text(InviteController.formatMessage), findsOneWidget);
      expect(env.prefs.referralCode, isNull);

      await tester.enterText(find.byKey(const Key('invite-code')), 'ABCD');
      await tester.pump();
      expect(find.text(InviteController.formatMessage), findsNothing);
    });

    testWidgets('code enregistré comme parrainage marchand, puis connexion', (tester) async {
      final env = await pumpInvite(tester);
      await tester.enterText(find.byKey(const Key('invite-code')), 'ref-xyz123');
      await tester.pump();
      await tester.tap(find.byKey(const Key('invite-submit')));
      await tester.pump();
      await tester.pump();
      expect(find.text("Code d'invitation enregistré"), findsOneWidget);
      expect(find.text('Bienvenue'), findsOneWidget);
      expect(env.prefs.referralCode, 'REF-XYZ123');
      expect(env.prefs.firstLaunchDone, isTrue);

      await tester.pump(InviteScreen.acceptedDelay);
      await tester.pumpAndSettle();
      expect(find.text('route:${Routes.login}'), findsOneWidget);
    });

    testWidgets('« J’ai déjà une carte » → connexion sans code', (tester) async {
      final env = await pumpInvite(tester);
      await tester.tap(find.byKey(const Key('invite-skip')));
      await tester.pumpAndSettle();
      expect(find.text('route:${Routes.login}'), findsOneWidget);
      expect(env.prefs.firstLaunchDone, isTrue);
      expect(env.prefs.referralCode, isNull);
    });

    testWidgets('« Je n’ai pas de code » → obtenir une invitation', (tester) async {
      await pumpInvite(tester);
      await tester.tap(find.byKey(const Key('invite-no-code')));
      await tester.pumpAndSettle();
      expect(find.text('route:${Routes.requestInvite}'), findsOneWidget);
    });
  });

  group('Liste d’attente (POST /waitlist, hors API)', () {
    testWidgets('numéro invalide → toast ; valide → position', (tester) async {
      usePhoneSize(tester);
      final env = await TestEnv.create();
      await env.pumpScreen(tester, const RequestInviteScreen());
      expect(find.text('Obtenir une invitation'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('waitlist-phone')), '12');
      await tester.tap(find.byKey(const Key('waitlist-submit')));
      await tester.pump();
      expect(find.text(WaitlistController.invalidPhoneMessage), findsOneWidget);

      await tester.enterText(find.byKey(const Key('waitlist-phone')), '+229 01 97 00 00 00');
      await tester.tap(find.byKey(const Key('waitlist-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('waitlist-done')), findsOneWidget);
      expect(find.text('Inscrit. Vous êtes n° 1287 sur la liste.'), findsOneWidget);
    });
  });
}
