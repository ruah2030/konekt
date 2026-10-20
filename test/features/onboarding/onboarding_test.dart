import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
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

    testWidgets('formatage XXXX-XXXX et bouton désactivé tant que incomplet', (tester) async {
      await pumpInvite(tester);
      expect(find.byKey(const Key('invite-video-fallback')), findsOneWidget);
      expect(find.text('SUR INVITATION'), findsOneWidget);
      expect(find.text('Votre carte vous attend'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('invite-code')), 'ab1c');
      await tester.pump();
      expect(find.text('AB1C'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('invite-code')), 'ab1c-d2e3f!9');
      await tester.pump();
      expect(find.text('AB1C-D2E3'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('code invalide → erreur inline', (tester) async {
      await pumpInvite(tester);
      await tester.enterText(find.byKey(const Key('invite-code')), '00000000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('invite-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('Code invalide ou déjà utilisé. Vérifiez-le auprès de la personne qui vous l’a donné.'),
        findsOneWidget,
      );
      // Modifier le code efface l'erreur.
      await tester.enterText(find.byKey(const Key('invite-code')), '0000000');
      await tester.pump();
      expect(find.byKey(const Key('invite-error')), findsNothing);
    });

    testWidgets('succès → invitation acceptée puis connexion après 1,5 s', (tester) async {
      final env = await pumpInvite(tester);
      await tester.enterText(find.byKey(const Key('invite-code')), 'KNKT2024');
      await tester.pump();
      await tester.tap(find.byKey(const Key('invite-submit')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Invitation de Rodrigue A. acceptée'), findsOneWidget);
      expect(find.text('Bienvenue'), findsOneWidget);
      expect(env.prefs.firstLaunchDone, isFalse);

      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pumpAndSettle();
      expect(find.text('route:${Routes.login}'), findsOneWidget);
      expect(env.prefs.firstLaunchDone, isTrue);
    });

    testWidgets('lien « pas de code » → obtenir une invitation', (tester) async {
      await pumpInvite(tester);
      await tester.tap(find.byKey(const Key('invite-no-code')));
      await tester.pumpAndSettle();
      expect(find.text('route:${Routes.requestInvite}'), findsOneWidget);
    });
  });

  group('Obtenir une invitation', () {
    Future<TestEnv> pumpRequest(WidgetTester tester) async {
      usePhoneSize(tester);
      final env = await TestEnv.create();
      await env.pumpScreen(tester, const RequestInviteScreen());
      await tester.pumpAndSettle();
      return env;
    }

    testWidgets('affiche les trois façons et inscrit sur la liste d’attente', (tester) async {
      await pumpRequest(tester);
      expect(find.text('Obtenir une invitation'), findsOneWidget);
      expect(find.text('Auprès d’un proche'), findsOneWidget);
      expect(find.text('Chez un point marchand'), findsOneWidget);
      expect(find.text('Liste d’attente'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('waitlist-phone')), '+229 01 96 66 62 62');
      await tester.tap(find.byKey(const Key('waitlist-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Inscrit. Vous êtes n° 214 sur la liste.'), findsOneWidget);
      expect(find.byKey(const Key('waitlist-submit')), findsNothing);
    });

    testWidgets('numéro invalide → message', (tester) async {
      await pumpRequest(tester);
      await tester.enterText(find.byKey(const Key('waitlist-phone')), '12');
      await tester.tap(find.byKey(const Key('waitlist-submit')));
      await tester.pump();
      expect(find.text('Numéro de téléphone invalide.'), findsOneWidget);
      expect(find.byKey(const Key('waitlist-done')), findsNothing);
    });
  });
}
