import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:konekt/app/app.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/onboarding/data/invite_link_service.dart';
import 'package:konekt/features/onboarding/presentation/screens/invite_screen.dart';
import 'package:konekt/features/onboarding/presentation/widgets/invite_link_listener.dart';

import '../../helpers/test_app.dart';
import '../auth/router_harness.dart';

void main() {
  group('InviteLinkService.parse', () {
    String? parse(String link) => InviteLinkService.parse(Uri.parse(link));

    test('lien https konekt.app/invite', () {
      expect(parse('https://konekt.app/invite?code=REF-XYZ123'), 'REF-XYZ123');
      expect(parse('https://www.konekt.app/invite/?code=ref-xyz123'), 'REF-XYZ123');
      expect(parse('https://konekt.app/invite?utm_source=sms&code=%20REF_1234%20'), 'REF_1234');
    });

    test('schéma konekt://invite', () {
      expect(parse('konekt://invite?code=REF-XYZ123'), 'REF-XYZ123');
      expect(parse('KONEKT://INVITE?code=abcd'), 'ABCD');
      expect(parse('konekt:///invite?code=REF-XYZ123'), 'REF-XYZ123');
    });

    test('autres liens ignorés', () {
      expect(parse('http://konekt.app/invite?code=REF-XYZ123'), isNull);
      expect(parse('https://evil.example/invite?code=REF-XYZ123'), isNull);
      expect(parse('https://konekt.app/pay?code=REF-XYZ123'), isNull);
      expect(parse('https://konekt.app/invite/extra?code=REF-XYZ123'), isNull);
      expect(parse('konekt://pay?code=REF-XYZ123'), isNull);
      expect(parse('autre://invite?code=REF-XYZ123'), isNull);
    });

    test('code absent, invalide ou trop long', () {
      expect(parse('konekt://invite'), isNull);
      expect(parse('konekt://invite?code='), isNull);
      expect(parse('konekt://invite?ref=REF-XYZ123'), isNull);
      expect(parse('konekt://invite?code=AB1'), isNull);
      expect(parse('konekt://invite?code=-ABCD'), isNull);
      expect(parse('konekt://invite?code=REF%20XYZ'), isNull);
      expect(parse('konekt://invite?code=REF!XYZ'), isNull);
      expect(parse('konekt://invite?code=${'A' * 40}'), 'A' * 40);
      expect(parse('konekt://invite?code=${'A' * 41}'), isNull);
    });
  });

  group('InviteLinkService', () {
    test('lien initial → code enregistré (au lancement), écho du flux ignoré', () async {
      final env = await TestEnv.create(prefs: {'merchant_referral_code': 'ANCIEN'});
      final links = StreamController<Uri>();
      final initial = Uri.parse('konekt://invite?code=ref-xyz123');
      final service = InviteLinkService(
        source: StaticInviteLinkSource(initial: initial, links: links.stream),
        prefs: env.prefs,
      );
      final received = <ReceivedInviteCode>[];
      await service.start(received.add);
      expect(env.prefs.referralCode, 'REF-XYZ123');
      expect(received.single.code, 'REF-XYZ123');
      expect(received.single.atLaunch, isTrue);

      // app_links renvoie aussi le lien de lancement dans le flux.
      links.add(initial);
      await pumpEventQueue();
      expect(received, hasLength(1));

      links.add(Uri.parse('https://konekt.app/invite?code=REF-NOUVEAU'));
      await pumpEventQueue();
      expect(env.prefs.referralCode, 'REF-NOUVEAU');
      expect(received.last.atLaunch, isFalse);

      // Lien invalide : rien ne change.
      links.add(Uri.parse('konekt://invite?code=x'));
      await pumpEventQueue();
      expect(env.prefs.referralCode, 'REF-NOUVEAU');
      expect(received, hasLength(2));

      await service.dispose();
      await links.close();
    });

    test('source en échec : pas d’erreur, rien d’enregistré', () async {
      final env = await TestEnv.create();
      final service = InviteLinkService(source: _FailingSource(), prefs: env.prefs);
      final received = <ReceivedInviteCode>[];
      await service.start(received.add);
      await pumpEventQueue();
      expect(received, isEmpty);
      expect(env.prefs.referralCode, isNull);
      await service.dispose();
    });
  });

  group('Application', () {
    Future<void> pumpAppWith(WidgetTester tester, TestEnv env, InviteLinkSource source) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...env.overrides, inviteLinkSourceProvider.overrideWithValue(source)],
          child: const KonektApp(useGoogleFonts: false),
        ),
      );
      await tester.pump();
    }

    testWidgets('lien reçu en session : code mémorisé, toast, session inchangée', (tester) async {
      final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: true));
      final links = StreamController<Uri>.broadcast();
      addTearDown(links.close);
      await pumpAppWith(tester, env, StaticInviteLinkSource(links: links.stream));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));
      final container = ProviderScope.containerOf(tester.element(find.byType(InviteLinkListener)));
      expect(container.read(authControllerProvider).status, AuthStatus.authenticated);

      links.add(Uri.parse('konekt://invite?code=REF-XYZ123'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(env.prefs.referralCode, 'REF-XYZ123');
      expect(find.text(InviteLinkListener.savedMessage), findsOneWidget);
      expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
      expect(container.read(cardSessionProvider), isNotNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('premier lancement par un lien : invitation pré-remplie et enregistrée, puis connexion', (
      tester,
    ) async {
      final env = await TestEnv.create();
      await pumpAppWith(
        tester,
        env,
        StaticInviteLinkSource(initial: Uri.parse('https://konekt.app/invite?code=REF-XYZ123')),
      );
      await tester.pump();
      expect(env.prefs.referralCode, 'REF-XYZ123');
      expect(env.prefs.firstLaunchDone, isFalse);

      // Fin du splash → écran d'invitation.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(InviteScreen), findsOneWidget);
      expect(find.byKey(const Key('invite-accepted')), findsOneWidget);
      expect(find.text('REF-XYZ123'), findsOneWidget);
      // Le badge de l'écran suffit : pas de toast pour un lien de lancement.
      expect(find.text(InviteLinkListener.savedMessage), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(env.prefs.firstLaunchDone, isTrue);

      await tester.pump(InviteScreen.acceptedDelay);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(InviteScreen), findsNothing);
    });
  });

  group('Écran d’invitation', () {
    testWidgets('lien reçu pendant l’affichage : champ pré-rempli, état « enregistré », pas de toast', (tester) async {
      usePhoneSize(tester);
      final env = await TestEnv.create();
      final links = StreamController<Uri>.broadcast();
      addTearDown(links.close);
      final router = GoRouter(
        initialLocation: Routes.invite,
        routes: [
          GoRoute(
            path: Routes.invite,
            builder: (_, _) => const InviteLinkListener(child: InviteScreen()),
          ),
          GoRoute(path: Routes.login, builder: (_, _) => routeStub(Routes.login)),
        ],
      );
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [
          ...env.overrides,
          inviteLinkSourceProvider.overrideWithValue(StaticInviteLinkSource(links: links.stream)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(theme: AppTheme.light(useGoogleFonts: false), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(inviteLinkProvider), isNull);

      links.add(Uri.parse('konekt://invite?code=ref-abc123'));
      await tester.pump();
      await tester.pump();
      expect(find.text('REF-ABC123'), findsOneWidget);
      expect(find.byKey(const Key('invite-accepted')), findsOneWidget);
      expect(find.text('Bienvenue'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(env.prefs.referralCode, 'REF-ABC123');
      expect(env.prefs.firstLaunchDone, isTrue);

      await tester.pump(InviteScreen.acceptedDelay);
      await tester.pumpAndSettle();
      expect(find.text('route:${Routes.login}'), findsOneWidget);
    });
  });
}

class _FailingSource implements InviteLinkSource {
  @override
  Future<Uri?> initialLink() => Future.error(StateError('plugin absent'));

  @override
  Stream<Uri> get links => Stream.error(StateError('plugin absent'));
}
