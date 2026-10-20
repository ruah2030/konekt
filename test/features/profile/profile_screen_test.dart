import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/card.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
import 'package:konekt/features/account/presentation/account_providers.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/profile/presentation/screens/profile_screen.dart';

import '../../helpers/test_app.dart';

/// Hors routeur, l'écran reste affiché après la déconnexion (dans l'app, le routeur renvoie
/// au login) : on avance de quelques frames au lieu d'attendre un état stable.
Future<void> settleAfterLogout(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Titulaire et carte figés : hors routeur, l'écran resterait affiché après la déconnexion et
/// rechargerait ces données sans session (dans l'app, le routeur renvoie aussitôt au login).
final staticAccount = [
  holderProvider.overrideWith(
    (ref) async => const Holder(
      firstName: 'Awa',
      lastName: 'Houngbédji',
      fullName: 'Awa Houngbédji',
      initials: 'AH',
      maskedPhone: '+229 •• •• •• 456',
    ),
  ),
  cardProvider.overrideWith(StaticCard.new),
];

class StaticCard extends CardController {
  @override
  Future<CardInfo> build() async => const CardInfo(
    id: '121436474',
    last4: '4589',
    status: CardStatus.active,
    brand: 'VISA',
    product: 'Visa Virtual Standard',
    issuer: 'UBA Bénin',
    holderName: 'AWA HOUNGBÉDJI',
  );
}

void main() {
  Future<(TestEnv, ProviderContainer)> pump(WidgetTester tester, {bool hasPin = true, bool isolated = false}) async {
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: hasPin));
    if (isolated) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...env.overrides, ...staticAccount],
          child: MaterialApp(theme: AppTheme.light(useGoogleFonts: false), home: const ProfileScreen()),
        ),
      );
    } else {
      await env.pumpScreen(tester, const ProfileScreen());
    }
    final container = ProviderScope.containerOf(tester.element(find.byType(ProfileScreen)));
    container.read(authControllerProvider); // session restaurée, comme dans l'app
    await tester.pumpAndSettle();
    return (env, container);
  }

  testWidgets('en-tête, sécurité, préférences, session', (tester) async {
    await pump(tester);
    expect(find.text('AH'), findsOneWidget);
    expect(find.text('Awa Houngbédji'), findsOneWidget);
    expect(find.text('Carte •••• 4589'), findsOneWidget);
    expect(find.text('Sécurité'), findsOneWidget);
    expect(find.text('Changer mon code secret'), findsOneWidget);
    expect(find.text('Code secret oublié'), findsOneWidget);
    expect(find.text('Lève aussi un éventuel verrouillage'), findsOneWidget);
    expect(find.text('Appareils connectés'), findsOneWidget);
    expect(find.text('3 appareil(s)'), findsOneWidget);
    expect(find.text('Recevoir mes messages par'), findsOneWidget);
    for (final l in ['SMS', 'E-mail', 'WhatsApp', 'Auto']) {
      expect(find.text(l), findsOneWidget);
    }
    expect(
      find.text('Un seul message par événement. Une carte déclarée perdue est signalée sur tous les canaux.'),
      findsOneWidget,
    );
    expect(find.text('Se déconnecter'), findsOneWidget);
    expect(find.text('Déconnecter tous mes appareils'), findsOneWidget);
    expect(find.text('En cas de téléphone perdu'), findsOneWidget);
    expect(find.text('MYCARD KONEKT 2.0 · POWERED BY BESTCASH'), findsOneWidget);
  });

  testWidgets('sans PIN : « Créer mon code secret »', (tester) async {
    final (_, container) = await pump(tester, hasPin: false);
    expect(container.read(authControllerProvider).hasPin, isFalse);
    expect(find.text('Créer mon code secret'), findsOneWidget);
  });

  testWidgets('choix du canal → enregistré sur le serveur', (tester) async {
    final (env, _) = await pump(tester);
    await tester.tap(find.byKey(const Key('channel-email')));
    await tester.pumpAndSettle();
    expect(env.db.channelPreference, 'EMAIL');
    expect(find.text('Préférence enregistrée.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('channel-auto')));
    await tester.pumpAndSettle();
    expect(env.db.channelPreference, isNull);
  });

  testWidgets('se déconnecter → non authentifié', (tester) async {
    final (env, container) = await pump(tester, isolated: true);
    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
    await tester.tap(find.byKey(const Key('profile-logout')));
    await settleAfterLogout(tester);
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(env.db.accessTokens, isEmpty);
    expect(await env.store.accessToken, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('déconnecter tous mes appareils → confirmation puis toast', (tester) async {
    final (env, container) = await pump(tester, isolated: true);
    await tester.tap(find.byKey(const Key('profile-logout-all')));
    await tester.pumpAndSettle();
    expect(find.text('Déconnecter tous les appareils ?'), findsOneWidget);
    expect(
      find.text('Toutes vos sessions seront fermées, y compris celle-ci. Il faudra vous reconnecter avec votre carte.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settleAfterLogout(tester);
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(find.text('3 sessions fermées.'), findsOneWidget);
    expect(env.db.accessTokens, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
