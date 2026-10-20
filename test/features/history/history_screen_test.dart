import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/history/presentation/providers/history_providers.dart';

import '../../helpers/test_app.dart';
import '../payment/payment_test_utils.dart';

void main() {
  testWidgets('deux onglets ; tap sur une opération → reçu ; Terminé → historique', (tester) async {
    final env = await TestEnv.create(signedIn: true);
    final container = paymentContainer(env);
    addTearDown(container.dispose);
    await pumpRouted(tester, container, Routes.history);
    await tester.pumpAndSettle();

    expect(find.text('Historique'), findsWidgets);
    expect(find.text('Mouvements'), findsOneWidget);
    expect(find.text('Mes opérations'), findsOneWidget);
    expect(find.text("Relevé lu en direct chez l'émetteur, sur le dernier mois."), findsOneWidget);
    expect(find.text('JUMIA BJ · Paiement en ligne'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-tab-ops')));
    await tester.pumpAndSettle();
    expect(find.text('Paiements lancés depuis Konekt avec leur statut. Touchez pour voir le reçu.'), findsOneWidget);
    expect(find.text('Échoué'), findsOneWidget);

    await tester.tap(find.byKey(const Key('op-op_6H1M')));
    await tester.pumpAndSettle();
    expect(find.text('Reçu'), findsOneWidget);
    expect(find.text('Paiement échoué'), findsOneWidget);

    await tester.tap(find.byKey(const Key('receipt-done')));
    await tester.pumpAndSettle();
    expect(find.text('Mes opérations'), findsOneWidget);
    expect(find.text('Reçu'), findsNothing);
  });

  testWidgets('état vide', (tester) async {
    final db = FakeDb()..transactions.clear();
    final env = await TestEnv.create(signedIn: true, db: db);
    final container = paymentContainer(env);
    addTearDown(container.dispose);
    await pumpRouted(tester, container, Routes.history);
    await tester.pumpAndSettle();
    expect(find.text('Aucun mouvement pour le moment.'), findsOneWidget);
  });

  test('pagination par curseur et invalidation', () async {
    final db = FakeDb();
    for (var i = 0; i < 30; i++) {
      db.operations.add({...db.operations.first, 'id': 'op_X$i'});
    }
    final env = await TestEnv.create(signedIn: true, db: db);
    final container = env.container();
    addTearDown(container.dispose);
    container.listen(operationsHistoryProvider, (_, _) {});

    final first = await container.read(operationsHistoryProvider.future);
    expect(first.items, hasLength(20));
    expect(first.hasMore, isTrue);

    await container.read(operationsHistoryProvider.notifier).loadMore();
    final all = container.read(operationsHistoryProvider).value!;
    expect(all.items, hasLength(33));
    expect(all.hasMore, isFalse);

    db.operations.removeRange(3, 33);
    await container.read(operationsHistoryProvider.notifier).refresh();
    expect(container.read(operationsHistoryProvider).value!.items, hasLength(3));
  });
}
