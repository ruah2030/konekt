import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/card.dart';
import 'package:konekt/core/domain/service_type.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/result.dart';
import 'package:konekt/features/account/data/account_repository.dart';
import 'package:konekt/features/home/data/home_card_repository.dart';
import 'package:konekt/features/home/presentation/widgets/home_services.dart';
import 'package:konekt/core/network/fake/fake_api.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/design_system/design_system.dart';
import 'package:konekt/features/home/presentation/screens/home_screen.dart';
import 'package:konekt/features/home/presentation/widgets/home_top_section.dart';

import '../../helpers/test_app.dart';
import 'home_test_utils.dart';

Future<TestEnv> pumpHome(WidgetTester tester, {FakeDb? db, void Function(TestEnv env)? setup}) async {
  final env = await TestEnv.create(signedIn: true, db: db);
  setup?.call(env);
  await pumpRouted(tester, env, const HomeScreen());
  return env;
}

class _FailingRepo extends HomeCardRepository {
  _FailingRepo() : super(Dio());

  @override
  Future<Result<void>> reactivate(String cardCustomerId) async =>
      const Err(ApiFailure(code: 'INTERNAL_ERROR', message: 'Impossible de joindre l’émetteur de la carte.'));
}

String balanceText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('home-balance'))).data!;

/// Repli si le domaine carte n'a pas encore enregistré `PATCH /cards/status` (le premier handler
/// correspondant répond : celui-ci n'est utilisé que si la route n'existe pas).
void registerStatusFallback(TestEnv env, List<Map<String, dynamic>> calls) {
  env.api.on(
    'PATCH',
    '/cards/status',
    (r) {
      calls.add(r.body);
      final previous = env.db.cardStatus;
      env.db.cardStatus = '${r.body['newStatus']}';
      return FakeResponse.ok({
        'success': true,
        'operationId': env.db.id('clop'),
        'previousStatus': previous,
        'newStatus': env.db.cardStatus,
      });
    },
    fields: {
      'cardCustomerId',
      'cardTierSlug',
      'newStatus',
      'phoneCountryCode',
      'phoneNumber',
      'acknowledgeIrreversible',
    },
  );
}

void main() {
  group('balanceDisplay', () {
    test('applique les règles par statut', () {
      expect(balanceDisplay(status: CardStatus.preActive, balance: null, hidden: false), (amount: '0', unit: 'FCFA'));
      for (final s in [CardStatus.inactive, CardStatus.lostOrStolen, CardStatus.deactivated]) {
        expect(balanceDisplay(status: s, balance: null, hidden: false, failed: true), (amount: '—', unit: ''));
      }
      expect(balanceDisplay(status: CardStatus.active, balance: 5000, hidden: true), (amount: '••• •••', unit: 'FCFA'));
      expect(balanceDisplay(status: CardStatus.active, balance: 720.15, hidden: false).amount, formatNumber(720));
      expect(balanceDisplay(status: CardStatus.active, balance: null, hidden: false, failed: true).amount, '—');
    });
  });

  testWidgets('carte active : nom, carte, solde, pastille = unread-count, catalogue', (tester) async {
    await pumpHome(
      tester,
      setup: (env) => env.db.addNotification('Bienvenue', 'Votre carte est prête.', kind: 'SUCCESS'),
    );

    expect(find.text('Bonjour Awa'), findsOneWidget);
    expect(find.text('Carte •••• 4589'), findsOneWidget);
    expect(balanceText(tester), formatNumber(152400));
    expect(find.byKey(const Key('card-alert')), findsNothing);
    expect(find.byKey(const Key('incident-banner')), findsNothing);
    // 2 non lues dans le jeu de données + 1 ajoutée : la pastille vient du serveur.
    expect(tester.widget<Text>(find.byKey(const Key('unread-count'))).data, '3');

    expect(find.text('Payer et recharger'), findsOneWidget);
    expect(find.text('Bientôt'), findsNothing);
    // Tous les services du catalogue sont disponibles (TV et facture d'électricité comprises).
    expect(find.byKey(const Key('catalog-tv')), findsOneWidget);
    expect(find.byKey(const Key('catalog-elecBill')), findsOneWidget);
    expect(find.text('Indisponible'), findsNothing);
    await tester.tap(find.byKey(const Key('catalog-tv')));
    await settle(tester);
    expect(find.text('Service tv'), findsOneWidget);
  });

  testWidgets('derniers mouvements avec signe déduit du solde courant', (tester) async {
    await pumpHome(tester);
    expect(find.text('Transfert sortant'), findsOneWidget);
    expect(find.text(formatSignedFcfa(-50440)), findsOneWidget);
    expect(find.text(formatSignedFcfa(100000)), findsOneWidget);
  });

  testWidgets('incident : bannière et électricité grisée (tap → motif)', (tester) async {
    await pumpHome(tester, db: FakeDb(incident: true));

    expect(find.byKey(const Key('incident-banner')), findsOneWidget);
    expect(find.textContaining('Électricité prépayée'), findsWidgets);

    await tester.tap(find.byKey(const Key('catalog-elec')));
    await settle(tester, 2);
    expect(find.text('Momentanément indisponible — nos équipes travaillent au rétablissement.'), findsOneWidget);
    expect(find.textContaining('Service elec'), findsNothing);
  });

  test('service absent du catalogue : ouvrable', () {
    expect(offerFor(const [], ServiceType.cash), isNull);
    const offer = ServiceOffer(
      key: 'cash-withdrawal',
      label: 'Retrait au guichet',
      kind: 'CATALOG',
      amountMode: 'FREE',
      available: false,
      unavailableReason: 'En maintenance.',
    );
    expect(offerFor(const [offer], ServiceType.cash), same(offer));
    expect(offerFor(const [offer], ServiceType.elec), isNull);
  });

  testWidgets('carte suspendue : « — » sans erreur, alerte, réactivation → Active', (tester) async {
    final calls = <Map<String, dynamic>>[];
    final env = await pumpHome(
      tester,
      db: FakeDb(cardStatus: 'Inactive'),
      setup: (env) => registerStatusFallback(env, calls),
    );

    expect(balanceText(tester), '—');
    expect(find.byType(ErrorView), findsNothing);
    expect(find.byKey(const Key('card-alert')), findsOneWidget);
    expect(find.text(CardStatus.inactive.blockedMessage), findsOneWidget);

    await tester.tap(find.byKey(const Key('card-alert-cta')));
    await settle(tester, 3);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);

    expect(env.db.cardStatus, 'Active');
    if (calls.isNotEmpty) {
      expect(calls.single, {'cardCustomerId': env.db.sessionCardId, 'newStatus': 'Active'});
    }
    expect(find.text('Carte réactivée.'), findsOneWidget);
    expect(find.byKey(const Key('card-alert')), findsNothing);
    expect(balanceText(tester), formatNumber(152400));
  });

  testWidgets('réactivation refusée : message du serveur', (tester) async {
    final env = await TestEnv.create(signedIn: true, db: FakeDb(cardStatus: 'Inactive'));
    await pumpRouted(
      tester,
      env,
      const HomeScreen(),
      extra: [homeCardRepositoryProvider.overrideWithValue(_FailingRepo())],
    );
    await tester.tap(find.byKey(const Key('card-alert-cta')));
    await settle(tester, 3);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);
    expect(find.text('Impossible de joindre l’émetteur de la carte.'), findsOneWidget);
    expect(find.byKey(const Key('card-alert')), findsOneWidget);
    expect(find.text('Carte réactivée.'), findsNothing);
  });

  testWidgets('carte à activer : solde 0', (tester) async {
    await pumpHome(tester, db: FakeDb(cardStatus: 'PreActive'));
    expect(balanceText(tester), '0');
    expect(find.byType(ErrorView), findsNothing);
    expect(find.text('Recharger ma carte'), findsOneWidget);
  });

  testWidgets('carte désactivée : « — », support', (tester) async {
    await pumpHome(tester, db: FakeDb(cardStatus: 'Deactivated'));
    expect(balanceText(tester), '—');
    expect(find.text(CardStatus.deactivated.blockedMessage), findsOneWidget);
    expect(find.text('Contacter le support'), findsOneWidget);
  });
}
