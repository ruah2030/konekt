import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/card.dart';
import 'package:konekt/core/network/fake/fake_api.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/result.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
import 'package:konekt/features/account/data/account_repository.dart';
import 'package:konekt/features/account/presentation/account_providers.dart';
import 'package:konekt/features/home/data/home_card_repository.dart';
import 'package:konekt/features/home/presentation/screens/home_screen.dart';
import 'package:konekt/features/home/presentation/widgets/home_sections.dart';
import 'package:konekt/features/home/presentation/widgets/home_top_section.dart';

import '../../helpers/test_app.dart';

/// Laisse le faux backend répondre sans `pumpAndSettle` (rotation des publicités = timer périodique).
Future<void> settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<TestEnv> pumpHome(WidgetTester tester, {FakeDb? db}) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final env = await TestEnv.create(signedIn: true, db: db);
  await env.pumpScreen(tester, const HomeScreen());
  await settle(tester);
  return env;
}

/// Comme [TestEnv.pumpScreen], avec des overrides supplémentaires.
Future<void> pumpWith(WidgetTester tester, TestEnv env, List<Override> extra) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...env.overrides, ...extra],
      child: MaterialApp(
        theme: AppTheme.light(useGoogleFonts: false),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomeScreen(),
      ),
    ),
  );
  await settle(tester);
}

class _FailingRepo extends HomeCardRepository {
  _FailingRepo() : super(Dio());

  @override
  Future<Result<void>> reactivate() async =>
      const Err(ApiFailure(code: 'FORBIDDEN', message: 'Réactivation impossible pour le moment.'));
}

String balanceText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('home-balance'))).data!;

void main() {
  group('balanceDisplay', () {
    test('applique les règles par statut', () {
      expect(balanceDisplay(status: CardStatus.preActive, balance: 5000, hidden: false), (amount: '0', unit: 'FCFA'));
      expect(balanceDisplay(status: CardStatus.inactive, balance: 5000, hidden: false), (amount: '—', unit: ''));
      expect(balanceDisplay(status: CardStatus.lostOrStolen, balance: 5000, hidden: true), (amount: '—', unit: ''));
      expect(balanceDisplay(status: CardStatus.active, balance: 5000, hidden: true), (amount: '••• •••', unit: 'FCFA'));
      expect(balanceDisplay(status: CardStatus.active, balance: 5000, hidden: false).amount, formatNumber(5000));
    });
  });

  testWidgets('carte active : en-tête, solde formaté, transactions, badge non-lus', (tester) async {
    await pumpHome(tester);

    expect(find.text('Bonjour Awa'), findsOneWidget);
    expect(find.text('Carte •••• 4589'), findsOneWidget);
    expect(find.text('AH'), findsOneWidget);
    expect(balanceText(tester), formatNumber(152400));
    expect(find.text('FCFA'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.byKey(const Key('card-alert')), findsNothing);
    expect(find.byKey(const Key('incident-banner')), findsNothing);

    // 2 notifications non lues dans le jeu de données.
    expect(tester.widget<Text>(find.byKey(const Key('unread-count'))).data, '2');

    expect(find.text('Payer et recharger'), findsOneWidget);
    expect(find.text('Bientôt'), findsOneWidget);
    expect(find.text('Envoi à Afiavi Sossou'), findsOneWidget);
    expect(find.byKey(const Key('tx-tx_4')), findsOneWidget);
    expect(find.text('POWERED BY BESTCASH CARDS BÉNIN'), findsOneWidget);
  });

  testWidgets('masquer le solde est persisté', (tester) async {
    final env = await pumpHome(tester);

    await tester.tap(find.byKey(const Key('toggle-balance')));
    await settle(tester, 2);
    expect(balanceText(tester), '••• •••');
    expect(find.text('FCFA'), findsOneWidget);
    expect(env.prefs.hideBalance, isTrue);

    await tester.tap(find.byKey(const Key('toggle-balance')));
    await settle(tester, 2);
    expect(balanceText(tester), formatNumber(152400));
  });

  testWidgets('carte suspendue : « — », alerte, actions bloquées, réactivation', (tester) async {
    final db = FakeDb(cardStatus: 'INACTIVE');
    final env = await TestEnv.create(signedIn: true, db: db);
    // Repli si le handler du domaine carte n'est pas enregistré (le premier handler correspondant répond).
    env.api.on('POST', '/v1/card/reactivate', (_) {
      db.cardStatus = 'ACTIVE';
      return FakeResponse.ok(db.cardJson());
    });
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await env.pumpScreen(tester, const HomeScreen());
    await settle(tester);

    expect(balanceText(tester), '—');
    expect(find.text('FCFA'), findsNothing);
    expect(find.byKey(const Key('toggle-balance')), findsNothing);
    expect(find.text(CardStatus.inactive.blockedMessage), findsOneWidget);

    // Action rapide refusée tant que la carte est suspendue.
    await tester.tap(find.byKey(const Key('quick-transfer')));
    await settle(tester, 2);
    expect(find.text(CardStatus.inactive.blockedMessage), findsNWidgets(2));

    await tester.tap(find.text('Réactiver ma carte'));
    await settle(tester, 3);
    expect(find.text('Réactiver ma carte ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);

    expect(db.cardStatus, 'ACTIVE');
    expect(find.text('Carte réactivée.'), findsOneWidget);
    expect(find.byKey(const Key('card-alert')), findsNothing);
    expect(find.text('Active'), findsOneWidget);
    expect(balanceText(tester), formatNumber(152400));
  });

  testWidgets('réactivation annulée : aucun appel', (tester) async {
    final db = FakeDb(cardStatus: 'INACTIVE');
    final env = await TestEnv.create(signedIn: true, db: db);
    await env.pumpScreen(tester, const HomeScreen());
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('card-alert-cta')));
    await tester.tap(find.byKey(const Key('card-alert-cta')));
    await settle(tester, 3);
    await tester.tap(find.byKey(const Key('confirm-dialog-cancel')));
    await settle(tester, 3);
    expect(db.cardStatus, 'INACTIVE');
    expect(find.byKey(const Key('card-alert')), findsOneWidget);
  });

  testWidgets('échec de la réactivation : message d’erreur, statut inchangé', (tester) async {
    final env = await TestEnv.create(signedIn: true, db: FakeDb(cardStatus: 'INACTIVE'));
    await pumpWith(tester, env, [homeCardRepositoryProvider.overrideWithValue(_FailingRepo())]);
    await tester.ensureVisible(find.byKey(const Key('card-alert-cta')));
    await tester.tap(find.byKey(const Key('card-alert-cta')));
    await settle(tester, 3);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);
    expect(find.text('Réactivation impossible pour le moment.'), findsOneWidget);
    expect(find.byKey(const Key('card-alert')), findsOneWidget);
  });

  testWidgets('carte à activer : 0 FCFA, pas de transactions, support', (tester) async {
    await pumpHome(tester, db: FakeDb(cardStatus: 'PRE_ACTIVE'));

    expect(balanceText(tester), '0');
    expect(find.text('FCFA'), findsOneWidget);
    expect(find.text("Aucune transaction pour l'instant."), findsOneWidget);
    expect(find.text(CardStatus.preActive.blockedMessage), findsOneWidget);

    await tester.tap(find.text('Contacter le support'));
    await settle(tester, 2);
    expect(find.text(supportMessage), findsOneWidget);
  });

  testWidgets('carte perdue : « — » et support', (tester) async {
    await pumpHome(tester, db: FakeDb(cardStatus: 'LOST_OR_STOLEN'));
    expect(balanceText(tester), '—');
    expect(find.text('Contacter le support'), findsOneWidget);
    expect(find.text('Bloquée'), findsOneWidget);
  });

  testWidgets('« Ma carte » refusée si la carte n’est pas active', (tester) async {
    await pumpHome(tester, db: FakeDb(cardStatus: 'PRE_ACTIVE'));
    await tester.tap(find.byKey(const Key('quick-card')));
    await settle(tester, 2);
    expect(find.text(CardStatus.preActive.blockedMessage), findsNWidgets(2));
  });

  testWidgets('bannière incident opérateur', (tester) async {
    await pumpHome(tester, db: FakeDb(incident: true));
    expect(find.byKey(const Key('incident-banner')), findsOneWidget);
    expect(find.text('Incident chez un opérateur : certains paiements peuvent être ralentis.'), findsOneWidget);
  });

  testWidgets('erreur de chargement des transactions puis réessai', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    var fail = true;
    await pumpWith(tester, env, [
      recentTransactionsProvider.overrideWith((ref) async {
        if (fail) throw const ApiFailure(code: 'SERVICE_UNAVAILABLE', message: 'Service indisponible.');
        return (await ref.watch(accountRepositoryProvider).transactions(limit: 4)).items;
      }),
    ]);
    expect(find.text('Service indisponible.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Réessayer'));
    await settle(tester);
    expect(find.text('Envoi à Afiavi Sossou'), findsOneWidget);
  });

  testWidgets('pull-to-refresh recharge le solde', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    await env.pumpScreen(tester, const HomeScreen());
    await settle(tester);
    env.db.balance = 99000;
    await tester.fling(find.text('Votre solde'), const Offset(0, 300), 1000);
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(balanceText(tester), formatNumber(99000));
  });
}
