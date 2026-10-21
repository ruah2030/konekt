import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/card.dart';
import 'package:konekt/core/domain/transaction.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/features/history/presentation/providers/history_providers.dart';
import 'package:konekt/features/history/presentation/screens/history_screen.dart';

import '../../helpers/test_app.dart';
import '../home/home_test_utils.dart';

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
}
