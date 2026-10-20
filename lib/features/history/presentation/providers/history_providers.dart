import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/operation.dart';
import '../../../../core/domain/transaction.dart';
import '../../../../core/network/api_failure.dart';
import '../../../account/data/account_repository.dart';

/// Liste paginée par curseur (scroll infini).
class PagedList<T> {
  const PagedList({this.items = const [], this.nextCursor, this.loadingMore = false, this.loadMoreError});
  final List<T> items;
  final String? nextCursor;
  final bool loadingMore;
  final ApiFailure? loadMoreError;

  bool get hasMore => nextCursor != null;
}

/// Contrôleur générique : première page au build, pages suivantes via [loadMore].
abstract class PagedController<T> extends AsyncNotifier<PagedList<T>> {
  static const pageSize = 20;

  Future<Page<T>> fetch({String? cursor});

  @override
  Future<PagedList<T>> build() async {
    final page = await fetch();
    return PagedList(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(PagedList(items: current.items, nextCursor: current.nextCursor, loadingMore: true));
    try {
      final page = await fetch(cursor: current.nextCursor);
      state = AsyncData(PagedList(items: [...current.items, ...page.items], nextCursor: page.nextCursor));
    } catch (e) {
      state = AsyncData(
        PagedList(items: current.items, nextCursor: current.nextCursor, loadMoreError: ApiFailure.from(e)),
      );
    }
  }

  /// Pull-to-refresh : recharge la première page.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

class TransactionsHistory extends PagedController<CardTransaction> {
  @override
  Future<Page<CardTransaction>> fetch({String? cursor}) =>
      ref.read(accountRepositoryProvider).transactions(cursor: cursor, limit: PagedController.pageSize);
}

class OperationsHistory extends PagedController<Operation> {
  @override
  Future<Page<Operation>> fetch({String? cursor}) =>
      ref.read(accountRepositoryProvider).operations(cursor: cursor, limit: PagedController.pageSize);
}

/// Onglet « Mouvements » (relevé émetteur).
final transactionsHistoryProvider = AsyncNotifierProvider<TransactionsHistory, PagedList<CardTransaction>>(
  TransactionsHistory.new,
);

/// Onglet « Mes opérations ».
final operationsHistoryProvider = AsyncNotifierProvider<OperationsHistory, PagedList<Operation>>(OperationsHistory.new);

/// À appeler après un paiement (ou un changement de session) pour recharger l'historique.
void invalidateHistory(WidgetRef ref) {
  ref
    ..invalidate(transactionsHistoryProvider)
    ..invalidate(operationsHistoryProvider);
}
