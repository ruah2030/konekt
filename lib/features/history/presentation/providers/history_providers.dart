import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/operation.dart';
import '../../../../core/domain/transaction.dart';
import '../../../../core/network/api_failure.dart';
import '../../../account/data/account_repository.dart';
import '../../../auth/presentation/providers/auth_controller.dart';

/// Carte de session (lue, pas écoutée : appelé hors `build`).
String _cardId(Ref ref) {
  final s = ref.read(cardSessionProvider);
  if (s == null) throw StateError('Aucune session porteur.');
  return s.cardCustomerId;
}

/// Liste chargée par morceaux (pages d'opérations ou mois du relevé).
class PagedList<T> {
  const PagedList({this.items = const [], this.nextCursor, this.loadingMore = false, this.loadMoreError});
  final List<T> items;

  /// Morceau suivant (numéro de page ou index de mois) ; null = tout est chargé.
  final String? nextCursor;
  final bool loadingMore;
  final ApiFailure? loadMoreError;

  bool get hasMore => nextCursor != null;
}

/// Contrôleur générique : premier morceau au build, suivants via [loadMore].
abstract class PagedController<T> extends AsyncNotifier<PagedList<T>> {
  static const pageSize = 20;

  Future<Page<T>> fetch({String? cursor});

  /// Raccorde un nouveau morceau aux éléments déjà chargés (par défaut : concaténation).
  List<T> merge(List<T> current, List<T> next) => [...current, ...next];

  @override
  Future<PagedList<T>> build() async {
    ref.watch(cardSessionProvider); // changement de carte → historique rechargé
    final page = await fetch();
    return PagedList(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(PagedList(items: current.items, nextCursor: current.nextCursor, loadingMore: true));
    try {
      final page = await fetch(cursor: current.nextCursor);
      state = AsyncData(PagedList(items: merge(current.items, page.items), nextCursor: page.nextCursor));
    } catch (e) {
      state = AsyncData(
        PagedList(items: current.items, nextCursor: current.nextCursor, loadMoreError: ApiFailure.from(e)),
      );
    }
  }

  /// Pull-to-refresh : recharge le premier morceau.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// « Mouvements » : relevé émetteur (`GET /cards/transactions/:id`) chargé mois par mois, du mois en
/// cours vers le passé ([maxMonths] au plus). Carte suspendue/bloquée → erreur 400 (relevé non lisible) ;
/// carte à activer → liste vide.
class TransactionsHistory extends PagedController<CardTransaction> {
  static const maxMonths = 12;

  /// Mois [index] (0 = mois en cours, jusqu'à aujourd'hui inclus).
  static ({DateTime start, DateTime end}) monthRange(DateTime now, int index) {
    final start = DateTime(now.year, now.month - index, 1);
    final end = index == 0 ? DateTime(now.year, now.month, now.day) : DateTime(now.year, now.month - index + 1, 0);
    return (start: start, end: end);
  }

  @override
  Future<Page<CardTransaction>> fetch({String? cursor}) async {
    final index = int.tryParse(cursor ?? '0') ?? 0;
    final range = monthRange(DateTime.now(), index);
    final items = await ref
        .read(accountRepositoryProvider)
        .transactions(_cardId(ref), start: range.start, end: range.end);
    return Page(items, index + 1 < maxMonths ? '${index + 1}' : null);
  }

  /// Le sens du dernier mouvement d'un mois se déduit du `runningBalance` du premier mouvement
  /// du mois précédent : on le corrige une fois ce mois chargé.
  @override
  List<CardTransaction> merge(List<CardTransaction> current, List<CardTransaction> next) {
    if (current.isEmpty || next.isEmpty) return [...current, ...next];
    return [...current.take(current.length - 1), fixDirection(current.last, next.first), ...next];
  }

  static CardTransaction fixDirection(CardTransaction tx, CardTransaction older) {
    final after = tx.balanceAfter;
    final before = older.balanceAfter;
    if (after == null || before == null || after == before) return tx;
    final credit = after > before;
    if (credit == tx.isCredit) return tx;
    // Crédit : montant de base ; débit : total (base + frais).
    final amount = credit ? tx.amount.abs() - tx.fee : -(tx.amount.abs() + tx.fee);
    return CardTransaction(
      id: tx.id,
      description: tx.description,
      amount: amount,
      fee: tx.fee,
      balanceAfter: tx.balanceAfter,
      createdAt: tx.createdAt,
      reference: tx.reference,
    );
  }
}

/// « Mes opérations » : `GET /operations` paginé (`page`/`limit`).
class OperationsHistory extends PagedController<Operation> {
  @override
  Future<Page<Operation>> fetch({String? cursor}) => ref
      .read(accountRepositoryProvider)
      .operations(cardCustomerId: _cardId(ref), cursor: cursor, limit: PagedController.pageSize);
}

/// Onglet « Mouvements » (relevé émetteur, par mois).
final transactionsHistoryProvider = AsyncNotifierProvider<TransactionsHistory, PagedList<CardTransaction>>(
  TransactionsHistory.new,
);

/// Onglet « Mes opérations ».
final operationsHistoryProvider = AsyncNotifierProvider<OperationsHistory, PagedList<Operation>>(OperationsHistory.new);

/// À appeler après un paiement (ou un changement de statut) pour recharger l'historique.
void invalidateHistory(WidgetRef ref) {
  ref
    ..invalidate(transactionsHistoryProvider)
    ..invalidate(operationsHistoryProvider);
}
