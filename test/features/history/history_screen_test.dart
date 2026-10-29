import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/card.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/core/domain/transaction.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/features/account/data/account_repository.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
import 'package:konekt/features/history/presentation/providers/history_providers.dart';
import 'package:konekt/features/history/presentation/screens/history_screen.dart';

import '../../helpers/test_app.dart';
import '../home/home_test_utils.dart';
import 'query_recorder.dart';

/// Relevé maîtrisé : deux mouvements ce mois-ci, un le mois précédent.
/// Le sens n'est pas fourni par l'émetteur : il se déduit du `runningBalance`.
FakeDb statementDb() {
  final db = FakeDb()..issuerTransactions.clear();
  final now = DateTime.now();
  db
    ..addIssuerTransaction(
      'Paiement Crédit MTN',
      -1000,
      at: DateTime(now.year, now.month - 1, 15, 12),
      runningBalance: 0,
    )
    // Libellé neutre : seul le solde courant du mois précédent révèle qu'il s'agit d'un crédit.
    ..addIssuerTransaction(
      'Opération GTP 4471',
      20000,
      at: now.subtract(const Duration(seconds: 20)),
      runningBalance: 20000,
    )
    ..addIssuerTransaction(
      'JUMIA BJ Paiement en ligne',
      -5000,
      fee: 100,
      at: now.subtract(const Duration(seconds: 10)),
      runningBalance: 14900,
    );
  return db;
}

Future<TestEnv> pumpHistory(WidgetTester tester, FakeDb db) async {
  final env = await TestEnv.create(signedIn: true, db: db);
  await pumpRouted(tester, env, const HistoryScreen());
  return env;
}

/// Opérations maîtrisées : statut, date et référence connus.
FakeDb operationsDb() {
  final db = FakeDb()..operations.clear();
  Map<String, dynamic> op(String status, num hours, String ref) => {
    ...db.newOperation(
      type: 'ADDON_SALE',
      status: status,
      serviceSlug: 'mobile-topup',
      serviceLabel: 'Recharge téléphonique',
      amount: 1000,
      at: db.hoursAgo(hours),
    ),
    'reference': ref,
  };
  db.operations.addAll([
    op('SUCCESS', 1, 'ADS-REF-RECENT-OK'),
    op('FAILED', 2, 'ADS-REF-RECENT-KO'),
    op('PENDING', 3, 'ADS-REF-RECENT-WAIT'),
    op('SUCCESS', 24 * 20, 'ADS-REF-OLD-OK'),
    op('SUCCESS', 24 * 60, 'ADS-REF-OLDER-OK'),
  ]);
  return db;
}

Future<(ProviderContainer, QueryRecorder)> historyContainer(FakeDb db) async {
  final env = await TestEnv.create(signedIn: true, db: db);
  final container = env.container();
  addTearDown(container.dispose);
  await TestEnv.waitForAuth(container);
  final recorder = QueryRecorder.attach(container);
  container
    ..listen(operationsHistoryProvider, (_, _) {})
    ..listen(transactionsHistoryProvider, (_, _) {});
  return (container, recorder);
}

String ymd(DateTime d) => AccountRepository.ymd(d);

void main() {
  test('monthRange : mois en cours jusqu’à aujourd’hui, puis mois complets', () {
    final now = DateTime(2026, 3, 18, 10);
    expect(TransactionsHistory.monthRange(now, 0), (start: DateTime(2026, 3), end: DateTime(2026, 3, 18)));
    expect(TransactionsHistory.monthRange(now, 1), (start: DateTime(2026, 2), end: DateTime(2026, 2, 28)));
    expect(TransactionsHistory.monthRange(now, 3), (start: DateTime(2025, 12), end: DateTime(2025, 12, 31)));
  });

  test('fixDirection : corrige le sens à la frontière de deux mois', () {
    final tx = CardTransaction(
      id: '1',
      description: 'X',
      amount: -20000,
      fee: 0,
      balanceAfter: 20000,
      createdAt: DateTime(2026),
    );
    final older = CardTransaction(
      id: '0',
      description: 'Y',
      amount: -1,
      fee: 0,
      balanceAfter: 0,
      createdAt: DateTime(2025),
    );
    expect(TransactionsHistory.fixDirection(tx, older).amount, 20000);
    expect(TransactionsHistory.fixDirection(tx, tx).amount, -20000);
  });

  testWidgets('Mouvements : mois en cours, signe déduit, puis mois précédent', (tester) async {
    await pumpHistory(tester, statementDb());

    expect(find.text('Mouvements'), findsOneWidget);
    expect(find.text('Mes opérations'), findsOneWidget);
    expect(find.text('JUMIA BJ Paiement en ligne'), findsOneWidget);
    expect(find.text(formatSignedFcfa(-5100)), findsOneWidget);
    expect(find.text('Opération GTP 4471'), findsOneWidget);
    expect(find.text('Paiement Crédit MTN'), findsNothing);

    await tester.tap(find.byKey(const Key('history-tx-more')));
    await settle(tester);

    expect(find.text('Paiement Crédit MTN'), findsOneWidget);
    expect(find.text(formatSignedFcfa(-1000)), findsOneWidget);
    // Le crédit du début de mois est confirmé par le solde du mois précédent.
    expect(find.text(formatSignedFcfa(20000)), findsOneWidget);
  });

  testWidgets('Mouvements : carte suspendue → message de statut', (tester) async {
    await pumpHistory(tester, FakeDb(cardStatus: 'Inactive'));
    expect(find.byKey(const Key('history-card-status')), findsOneWidget);
    expect(find.text(CardStatus.inactive.blockedMessage), findsOneWidget);
  });

  testWidgets('Mouvements : carte à activer → vide', (tester) async {
    await pumpHistory(tester, FakeDb(cardStatus: 'PreActive'));
    expect(find.text('Aucun mouvement sur cette période.'), findsOneWidget);
    expect(find.byKey(const Key('history-card-status')), findsNothing);
  });

  testWidgets('Mes opérations : statuts, pagination, tap → reçu', (tester) async {
    final db = FakeDb.demo();
    for (var i = 0; i < 6; i++) {
      db.operations.add(
        db.newOperation(
          type: 'ADDON_SALE',
          status: 'PENDING',
          serviceSlug: 'mobile-topup',
          serviceLabel: 'Recharge téléphonique',
          amount: 500,
          at: db.hoursAgo(2000 + i),
        ),
      );
    }
    expect(db.operations.length, greaterThan(20));
    await pumpHistory(tester, db);

    await tester.tap(find.byKey(const Key('history-tab-ops')));
    await settle(tester);
    expect(find.text('Paiements lancés depuis Konekt avec leur statut. Touchez pour voir le reçu.'), findsOneWidget);
    expect(find.byKey(Key('op-${db.operations.first['id']}')), findsOneWidget);
    expect(find.text('Échoué'), findsWidgets);

    final last = db.operations.last['id'];
    final more = find.byKey(const Key('history-ops-more'));
    if (more.evaluate().isNotEmpty) {
      await tester.ensureVisible(more);
      await tester.tap(more);
      await settle(tester);
    }
    await tester.scrollUntilVisible(find.byKey(Key('op-$last')), 300, scrollable: find.byType(Scrollable).last);
    expect(find.byKey(Key('op-$last')), findsOneWidget);

    await tester.tap(find.byKey(Key('op-$last')));
    await settle(tester);
    expect(find.text('Reçu $last history'), findsOneWidget);
  });

  test('opérations paginées (page/limit) et invalidation', () async {
    final db = FakeDb.demo();
    final total = db.operations.length;
    for (var i = 0; i < 30; i++) {
      db.operations.add({...db.operations.first, 'id': 'clop_x$i'});
    }
    final env = await TestEnv.create(signedIn: true, db: db);
    final container = env.container();
    addTearDown(container.dispose);
    await TestEnv.waitForAuth(container);
    container.listen(operationsHistoryProvider, (_, _) {});

    final first = await container.read(operationsHistoryProvider.future);
    expect(first.items, hasLength(20));
    expect(first.hasMore, isTrue);

    var pages = 1;
    while (container.read(operationsHistoryProvider).value!.hasMore) {
      await container.read(operationsHistoryProvider.notifier).loadMore();
      pages++;
    }
    expect(pages, ((total + 30) / 20).ceil());
    final all = container.read(operationsHistoryProvider).value!;
    expect(all.items, hasLength(total + 30));
    expect(all.hasMore, isFalse);

    db.operations.removeRange(3, db.operations.length);
    await container.read(operationsHistoryProvider.notifier).refresh();
    expect(container.read(operationsHistoryProvider).value!.items, hasLength(3));
  });

  group('filtres de « Mes opérations »', () {
    test('statut, période et recherche envoyés en query (jamais merchantId)', () async {
      final (c, rec) = await historyContainer(operationsDb());
      expect((await c.read(operationsHistoryProvider.future)).items, hasLength(5));
      expect(rec.queries('/operations').last, {'page': 1, 'limit': 20});

      final filter = c.read(operationsFilterProvider.notifier)..setStatus(OperationStatusFilter.success);
      var list = await c.read(operationsHistoryProvider.future);
      expect(rec.queries('/operations').last['status'], 'SUCCESS');
      expect(list.items.map((o) => o.reference), ['ADS-REF-RECENT-OK', 'ADS-REF-OLD-OK', 'ADS-REF-OLDER-OK']);

      filter.setPeriod(PeriodFilter.days30);
      list = await c.read(operationsHistoryProvider.future);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final q = rec.queries('/operations').last;
      expect(q['startDate'], ymd(today.subtract(const Duration(days: 29))));
      expect(q['endDate'], ymd(today));
      expect(list.items.map((o) => o.reference), ['ADS-REF-RECENT-OK', 'ADS-REF-OLD-OK']);

      filter
        ..setStatus(OperationStatusFilter.all)
        ..setPeriod(PeriodFilter.days7)
        ..setSearch('  recent-k ');
      list = await c.read(operationsHistoryProvider.future);
      final q2 = rec.queries('/operations').last;
      expect(q2['search'], 'recent-k');
      expect(q2.containsKey('status'), isFalse);
      expect(q2['startDate'], ymd(today.subtract(const Duration(days: 6))));
      expect(list.items.map((o) => o.reference), ['ADS-REF-RECENT-KO']);

      filter.setCustomRange(today.subtract(const Duration(days: 70)), today.subtract(const Duration(days: 10)));
      list = await c.read(operationsHistoryProvider.future);
      expect(list.items, isEmpty); // recherche « recent-k » toujours active
      filter.setSearch('');
      list = await c.read(operationsHistoryProvider.future);
      final q3 = rec.queries('/operations').last;
      expect(q3['startDate'], ymd(today.subtract(const Duration(days: 70))));
      expect(q3['endDate'], ymd(today.subtract(const Duration(days: 10))));
      expect(list.items.map((o) => o.reference), ['ADS-REF-OLD-OK', 'ADS-REF-OLDER-OK']);

      filter.clear();
      list = await c.read(operationsHistoryProvider.future);
      expect(list.items, hasLength(5));
      expect(rec.calls.where((r) => r.queryParameters.containsKey('merchantId')), isEmpty);
    });

    test('début > fin : refusé côté app, aucun appel', () async {
      final (c, rec) = await historyContainer(operationsDb());
      await c.read(operationsHistoryProvider.future);
      final sent = rec.calls.length;
      final today = DateTime.now();

      expect(
        () => c.read(operationsFilterProvider.notifier).setCustomRange(today, today.subtract(const Duration(days: 1))),
        throwsA(isA<ApiFailure>().having((f) => f.message, 'message', invalidRangeMessage)),
      );
      expect(c.read(operationsFilterProvider).period, PeriodFilter.all);

      await expectLater(
        c
            .read(accountRepositoryProvider)
            .operations(
              cardCustomerId: c.read(cardSessionProvider)!.cardCustomerId,
              startDate: today,
              endDate: today.subtract(const Duration(days: 1)),
            ),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        () => c.read(statementRangeProvider.notifier).set(today, today.subtract(const Duration(days: 3))),
        throwsA(isA<ApiFailure>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(rec.calls.length, sent);

      // Même jour : accepté.
      c.read(operationsFilterProvider.notifier).setCustomRange(today, today);
      await c.read(operationsHistoryProvider.future);
      expect(rec.calls.length, sent + 1);
    });

    test('faux backend : 400 si startDate > endDate, filtres operationType et statut validés', () async {
      final (c, _) = await historyContainer(operationsDb());
      final dio = c.read(dioProvider);
      Future<int?> status(Map<String, dynamic> q) async {
        try {
          return (await dio.get<Map<String, dynamic>>('/operations', queryParameters: q)).statusCode;
        } on DioException catch (e) {
          return e.response?.statusCode;
        }
      }

      expect(await status({'startDate': '2026-09-30', 'endDate': '2026-09-01'}), 400);
      expect(await status({'startDate': '2026-02-30'}), 400);
      expect(await status({'status': 'DONE'}), 400);
      expect(await status({'operationType': 'NOPE'}), 400);
      expect(await status({'merchantId': 'clm1'}), 403);
      final res = await dio.get<Map<String, dynamic>>('/operations', queryParameters: {'operationType': 'ADDON_SALE'});
      expect((res.data!['data'] as List), hasLength(5));
      final none = await dio.get<Map<String, dynamic>>(
        '/operations',
        queryParameters: {'operationType': 'WALLET_OPERATION'},
      );
      expect((none.data!['data'] as List), isEmpty);
      expect(none.data!['stats']['totalOperations'], 0);
    });

    testWidgets('puces, recherche avec anti-rebond, état vide filtré et « Effacer les filtres »', (tester) async {
      final db = operationsDb();
      await pumpHistory(tester, db);
      await tester.tap(find.byKey(const Key('history-tab-ops')));
      await settle(tester);
      for (final o in db.operations) {
        expect(find.byKey(Key('op-${o['id']}')), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('ops-status-failed')));
      await settle(tester);
      expect(find.byKey(Key('op-${db.operations[1]['id']}')), findsOneWidget);
      expect(find.byKey(Key('op-${db.operations[0]['id']}')), findsNothing);

      await tester.tap(find.byKey(const Key('ops-status-all')));
      await tester.enterText(find.byKey(const Key('ops-search')), 'INTROUVABLE');
      await tester.pump(const Duration(milliseconds: 200));
      // Anti-rebond : rien d'envoyé avant 400 ms.
      expect(find.byKey(Key('op-${db.operations[0]['id']}')), findsOneWidget);
      await settle(tester);
      expect(find.text('Aucune opération pour ces filtres'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ops-clear-filters')));
      await settle(tester);
      expect(find.text('Aucune opération pour ces filtres'), findsNothing);
      expect(find.byKey(Key('op-${db.operations[0]['id']}')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('ops-search'))).controller!.text, isEmpty);
    });
  });

  group('« Mouvements » sur une période personnalisée', () {
    test('startDate/endDate envoyés, une seule page', () async {
      final (c, rec) = await historyContainer(statementDb());
      final first = await c.read(transactionsHistoryProvider.future);
      expect(first.hasMore, isTrue);

      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 1, 1);
      final end = DateTime(now.year, now.month, now.day);
      c.read(statementRangeProvider.notifier).set(start, end);
      final list = await c.read(transactionsHistoryProvider.future);
      final q = rec.queries('/cards/transactions/${c.read(cardSessionProvider)!.cardCustomerId}').last;
      expect(q['startDate'], ymd(start));
      // Une date seule vaut minuit UTC : le lendemain est envoyé pour inclure la journée de fin.
      expect(q['endDate'], ymd(end.add(const Duration(days: 1))));
      expect(list.items.map((t) => t.description), contains('Paiement Crédit MTN'));
      expect(list.items, hasLength(3));
      expect(list.hasMore, isFalse);

      c.read(statementRangeProvider.notifier).clear();
      final back = await c.read(transactionsHistoryProvider.future);
      expect(back.hasMore, isTrue);
      expect(back.items, hasLength(2));
    });

    testWidgets('puce de période affichée', (tester) async {
      await pumpHistory(tester, statementDb());
      expect(find.byKey(const Key('tx-period-months')), findsOneWidget);
      expect(find.byKey(const Key('tx-period-custom')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tx-period-custom')));
      await settle(tester);
      expect(find.text('Choisir une période'), findsOneWidget);
    });
  });
}
