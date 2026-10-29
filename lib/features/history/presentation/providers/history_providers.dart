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
    // Pendant un rechargement (filtre changé), la page suivante de l'ancienne liste n'a plus de sens.
    if (current == null || !current.hasMore || current.loadingMore || state.isLoading) return;
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
/// carte à activer → liste vide. Si une période personnalisée est choisie ([statementRangeProvider]),
/// elle est chargée d'un seul tenant (`startDate`/`endDate`).
class TransactionsHistory extends PagedController<CardTransaction> {
  static const maxMonths = 12;

  /// Mois [index] (0 = mois en cours, jusqu'à aujourd'hui inclus).
  static ({DateTime start, DateTime end}) monthRange(DateTime now, int index) {
    final start = DateTime(now.year, now.month - index, 1);
    final end = index == 0 ? DateTime(now.year, now.month, now.day) : DateTime(now.year, now.month - index + 1, 0);
    return (start: start, end: end);
  }

  @override
  Future<PagedList<CardTransaction>> build() {
    ref.watch(statementRangeProvider);
    return super.build();
  }

  @override
  Future<Page<CardTransaction>> fetch({String? cursor}) async {
    final custom = ref.read(statementRangeProvider);
    if (custom != null) {
      final items = await ref
          .read(accountRepositoryProvider)
          .transactions(_cardId(ref), start: custom.start, end: custom.end);
      return Page(items, null);
    }
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

/// « Mes opérations » : `GET /operations` paginé (`page`/`limit`), avec les filtres de
/// [operationsFilterProvider] (changement de filtre → retour à la page 1).
class OperationsHistory extends PagedController<Operation> {
  @override
  Future<PagedList<Operation>> build() {
    ref.watch(operationsFilterProvider);
    return super.build();
  }

  @override
  Future<Page<Operation>> fetch({String? cursor}) {
    final filter = ref.read(operationsFilterProvider);
    final range = filter.range(DateTime.now());
    return ref
        .read(accountRepositoryProvider)
        .operations(
          cardCustomerId: _cardId(ref),
          cursor: cursor,
          limit: PagedController.pageSize,
          status: filter.status.api,
          startDate: range?.start,
          endDate: range?.end,
          search: filter.search,
        );
  }
}

// ---------------------------------------------------------------------------------------------------
// Filtres
// ---------------------------------------------------------------------------------------------------

/// Période de dates (jours inclus).
typedef DayRange = ({DateTime start, DateTime end});

/// Message affiché si la date de début est postérieure à la date de fin (vérifié avant tout appel).
const invalidRangeMessage = 'La date de début doit précéder la date de fin.';

/// Vérifie `startDate ≤ endDate` (au jour près) : [ApiFailure] locale sinon.
DayRange checkedRange(DateTime start, DateTime end) {
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  if (s.isAfter(e)) throw ApiFailure.local(ErrorCodes.validationFailed, invalidRangeMessage);
  return (start: s, end: e);
}

/// Statut d'opération filtré. L'API n'accepte qu'UN `status` par requête (`@IsEnum`) : chaque choix
/// correspond donc à une seule valeur. « En cours » = `PENDING` et « Échoués » = `FAILED` (les autres
/// statuts du groupe — `PROCESSING`, `CANCELLED`, `EXPIRED`… — restent visibles dans « Tous ») : un
/// filtrage côté client casserait la pagination serveur.
enum OperationStatusFilter {
  all(null, 'Tous'),
  success('SUCCESS', 'Réussis'),
  pending('PENDING', 'En cours'),
  failed('FAILED', 'Échoués');

  const OperationStatusFilter(this.api, this.label);
  final String? api;
  final String label;
}

/// Période prédéfinie des opérations.
enum PeriodFilter {
  all('Toute période'),
  days7('7 jours'),
  days30('30 jours'),
  months3('3 mois'),
  custom('Personnalisée');

  const PeriodFilter(this.label);
  final String label;
}

/// Filtres de « Mes opérations » (immuable).
class OperationsFilter {
  const OperationsFilter({
    this.status = OperationStatusFilter.all,
    this.period = PeriodFilter.all,
    this.custom,
    this.search = '',
  });

  final OperationStatusFilter status;
  final PeriodFilter period;

  /// Période personnalisée (si [period] == [PeriodFilter.custom]).
  final DayRange? custom;

  /// Recherche par référence (`search`).
  final String search;

  bool get isActive => status != OperationStatusFilter.all || period != PeriodFilter.all || search.trim().isNotEmpty;

  /// Bornes envoyées (`startDate`/`endDate`, jours inclus) ; null = pas de filtre de période.
  DayRange? range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (period) {
      PeriodFilter.all => null,
      PeriodFilter.days7 => (start: today.subtract(const Duration(days: 6)), end: today),
      PeriodFilter.days30 => (start: today.subtract(const Duration(days: 29)), end: today),
      PeriodFilter.months3 => (start: DateTime(today.year, today.month - 3, today.day), end: today),
      PeriodFilter.custom => custom,
    };
  }

  OperationsFilter copyWith({OperationStatusFilter? status, PeriodFilter? period, DayRange? custom, String? search}) =>
      OperationsFilter(
        status: status ?? this.status,
        period: period ?? this.period,
        custom: custom ?? this.custom,
        search: search ?? this.search,
      );

  @override
  bool operator ==(Object other) =>
      other is OperationsFilter &&
      other.status == status &&
      other.period == period &&
      other.custom == custom &&
      other.search == search;

  @override
  int get hashCode => Object.hash(status, period, custom, search);
}

class OperationsFilterController extends Notifier<OperationsFilter> {
  @override
  OperationsFilter build() {
    ref.watch(cardSessionProvider);
    return const OperationsFilter();
  }

  void setStatus(OperationStatusFilter status) => state = state.copyWith(status: status);

  /// Période prédéfinie (pas [PeriodFilter.custom] : voir [setCustomRange]).
  void setPeriod(PeriodFilter period) {
    assert(period != PeriodFilter.custom, 'Utiliser setCustomRange');
    state = OperationsFilter(status: state.status, period: period, search: state.search);
  }

  /// Période personnalisée ; lève une [ApiFailure] si [start] > [end] (filtre inchangé).
  void setCustomRange(DateTime start, DateTime end) =>
      state = state.copyWith(period: PeriodFilter.custom, custom: checkedRange(start, end));

  void setSearch(String search) {
    final s = search.trim();
    if (s != state.search) state = state.copyWith(search: s);
  }

  void clear() => state = const OperationsFilter();
}

final operationsFilterProvider = NotifierProvider<OperationsFilterController, OperationsFilter>(
  OperationsFilterController.new,
);

/// Période personnalisée du relevé « Mouvements » (null = mois par mois).
class StatementRangeController extends Notifier<DayRange?> {
  @override
  DayRange? build() {
    ref.watch(cardSessionProvider);
    return null;
  }

  /// Lève une [ApiFailure] si [start] > [end] (période inchangée).
  void set(DateTime start, DateTime end) => state = checkedRange(start, end);

  void clear() => state = null;
}

final statementRangeProvider = NotifierProvider<StatementRangeController, DayRange?>(StatementRangeController.new);

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
