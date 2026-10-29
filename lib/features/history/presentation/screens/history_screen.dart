import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/promotion.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/widgets/activity_tiles.dart';
import '../../../promotions/presentation/promo_slot.dart';
import '../providers/history_providers.dart';

/// Historique : relevé émetteur (« Mouvements ») et opérations Konekt (« Mes opérations »).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: const SliverAppBar.large(
                pinned: true,
                backgroundColor: KColors.background,
                title: Text('Historique'),
                bottom: TabBar(
                  labelColor: KColors.primary,
                  unselectedLabelColor: KColors.onSurfaceVariant,
                  indicatorColor: KColors.primary,
                  labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  tabs: [
                    Tab(key: Key('history-tab-tx'), text: 'Mouvements'),
                    Tab(key: Key('history-tab-ops'), text: 'Mes opérations'),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _HistoryTab(
                storageKey: 'history-tx',
                provider: transactionsHistoryProvider,
                note: "Relevé lu en direct chez l'émetteur, mois par mois ou sur la période choisie.",
                filters: const _StatementPeriodBar(),
                emptyMessage: 'Aucun mouvement sur cette période.',
                loadMoreLabel: 'Charger le mois précédent',
                autoLoad: false,
                tileBuilder: (context, tx, divider) => TransactionTile(tx, showDivider: divider),
              ),
              _HistoryTab(
                storageKey: 'history-ops',
                provider: operationsHistoryProvider,
                note: 'Paiements lancés depuis Konekt avec leur statut. Touchez pour voir le reçu.',
                filters: const _OperationsFilterBar(),
                emptyMessage: 'Aucune opération pour le moment.',
                emptyBuilder: (context, ref) => ref.watch(operationsFilterProvider).isActive
                    ? Column(
                        key: const Key('ops-empty-filtered'),
                        children: [
                          const EmptyState(message: 'Aucune opération pour ces filtres'),
                          TextButton(
                            key: const Key('ops-clear-filters'),
                            onPressed: ref.read(operationsFilterProvider.notifier).clear,
                            child: const Text('Effacer les filtres'),
                          ),
                        ],
                      )
                    : null,
                loadMoreLabel: 'Voir plus',
                tileBuilder: (context, op, divider) => OperationTile(
                  op,
                  showDivider: divider,
                  onTap: () => context.push(Routes.receipt(op.id, fromHistory: true)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryTab<T> extends ConsumerWidget {
  const _HistoryTab({
    required this.storageKey,
    required this.provider,
    required this.note,
    required this.emptyMessage,
    required this.tileBuilder,
    required this.loadMoreLabel,
    this.filters,
    this.emptyBuilder,
    this.autoLoad = true,
  });

  /// Barre de filtres affichée au-dessus de la liste.
  final Widget? filters;

  /// État vide personnalisé (null → [emptyMessage]).
  final Widget? Function(BuildContext context, WidgetRef ref)? emptyBuilder;

  final String storageKey;
  final AsyncNotifierProvider<PagedController<T>, PagedList<T>> provider;
  final String note;
  final String emptyMessage;
  final Widget Function(BuildContext context, T item, bool showDivider) tileBuilder;
  final String loadMoreLabel;

  /// Chargement automatique en fin de défilement (opérations) ; sinon bouton seul (mois du relevé).
  final bool autoLoad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final list = async.value;
    final items = list?.items ?? const [];

    Widget section(Widget child) => SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(child: child),
    );

    final slivers = <Widget>[
      SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        sliver: SliverToBoxAdapter(
          child: Text(
            note,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: KColors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      section(
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: PromoSlot(placement: PromoPlacement.history),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      if (filters != null) section(Padding(padding: const EdgeInsets.only(bottom: 12), child: filters)),
      if (list == null && async.hasError)
        section(_ErrorOrStatus(error: async.error!, onRetry: () => ref.invalidate(provider)))
      else if (list == null || (async.isLoading && !async.isRefreshing))
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (items.isEmpty)
        section(emptyBuilder?.call(context, ref) ?? EmptyState(message: emptyMessage))
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => DecoratedBox(
              decoration: BoxDecoration(
                color: KColors.surface,
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(16) : Radius.zero,
                  bottom: i == items.length - 1 ? const Radius.circular(16) : Radius.zero,
                ),
              ),
              child: Material(type: MaterialType.transparency, child: tileBuilder(context, items[i], i > 0)),
            ),
          ),
        ),
      if (list != null && list.loadingMore && !async.isLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      if (list?.loadMoreError != null) section(ErrorView(error: list!.loadMoreError!, onRetry: notifier.loadMore)),
      if (list != null && list.hasMore && !list.loadingMore && list.loadMoreError == null)
        section(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: TextButton(key: Key('$storageKey-more'), onPressed: notifier.loadMore, child: Text(loadMoreLabel)),
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (autoLoad && n.metrics.extentAfter < 400 && list != null && list.hasMore && list.loadMoreError == null) {
          notifier.loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: CustomScrollView(key: PageStorageKey(storageKey), slivers: slivers),
      ),
    );
  }
}

/// Erreur de premier chargement. Relevé refusé (400) pour une carte suspendue, perdue ou désactivée :
/// on affiche le message de statut du serveur plutôt qu'une erreur.
class _ErrorOrStatus extends StatelessWidget {
  const _ErrorOrStatus({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final f = ApiFailure.from(error);
    if (f.statusCode != 400 || f.code != ErrorCodes.requestRejected) return ErrorView(error: error, onRetry: onRetry);
    return Container(
      key: const Key('history-card-status'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: KColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.info_rounded, size: 22, color: KColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              f.message,
              style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Sélecteur de période (jours inclus) ; la vérification début ≤ fin est faite par le contrôleur.
Future<DateTimeRange?> _pickRange(BuildContext context, DayRange? initial) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(today.year - 3),
    lastDate: today,
    initialDateRange: initial == null ? null : DateTimeRange(start: initial.start, end: initial.end),
    helpText: 'Choisir une période',
    saveText: 'Valider',
  );
}

/// Applique [apply] ; une période invalide (début > fin) est signalée sans appel réseau.
void _applyRange(BuildContext context, void Function() apply) {
  try {
    apply();
  } on ApiFailure catch (f) {
    showToast(context, f.message);
  }
}

/// Filtres de « Mes opérations » : recherche par référence (anti-rebond), statut et période.
class _OperationsFilterBar extends ConsumerStatefulWidget {
  const _OperationsFilterBar();

  @override
  ConsumerState<_OperationsFilterBar> createState() => _OperationsFilterBarState();
}

class _OperationsFilterBarState extends ConsumerState<_OperationsFilterBar> {
  static const debounce = Duration(milliseconds: 400);

  late final _search = TextEditingController(text: ref.read(operationsFilterProvider).search);
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _timer?.cancel();
    _timer = Timer(debounce, () => ref.read(operationsFilterProvider.notifier).setSearch(value));
  }

  Future<void> _custom(OperationsFilter filter) async {
    final picked = await _pickRange(context, filter.custom);
    if (picked == null || !mounted) return;
    _applyRange(context, () => ref.read(operationsFilterProvider.notifier).setCustomRange(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(operationsFilterProvider);
    final ctrl = ref.read(operationsFilterProvider.notifier);
    // « Effacer les filtres » vide aussi le champ.
    ref.listen(operationsFilterProvider, (_, next) {
      if (next.search != _search.text.trim()) {
        _timer?.cancel();
        _search.text = next.search;
      }
    });
    final custom = filter.custom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('ops-search'),
          controller: _search,
          onChanged: _onSearch,
          onSubmitted: (v) {
            _timer?.cancel();
            ctrl.setSearch(v);
          },
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Rechercher une référence',
            prefixIcon: const Icon(Symbols.search_rounded),
            isDense: true,
            suffixIcon: filter.search.isEmpty
                ? null
                : IconButton(
                    key: const Key('ops-search-clear'),
                    tooltip: 'Effacer la recherche',
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () {
                      _timer?.cancel();
                      _search.clear();
                      ctrl.setSearch('');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        _ChipRow(
          children: [
            for (final s in OperationStatusFilter.values)
              ChoiceChip(
                key: Key('ops-status-${s.name}'),
                label: Text(s.label),
                selected: filter.status == s,
                onSelected: (_) => ctrl.setStatus(s),
              ),
          ],
        ),
        _ChipRow(
          children: [
            for (final p in PeriodFilter.values)
              ChoiceChip(
                key: Key('ops-period-${p.name}'),
                label: Text(
                  p == PeriodFilter.custom && filter.period == p && custom != null
                      ? '${_d(custom.start)} – ${_d(custom.end)}'
                      : p.label,
                ),
                selected: filter.period == p,
                onSelected: (_) => p == PeriodFilter.custom ? _custom(filter) : ctrl.setPeriod(p),
              ),
          ],
        ),
      ],
    );
  }
}

/// « Mouvements » : mois par mois (par défaut) ou période personnalisée (`startDate`/`endDate`).
class _StatementPeriodBar extends ConsumerWidget {
  const _StatementPeriodBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statementRangeProvider);
    final ctrl = ref.read(statementRangeProvider.notifier);
    return _ChipRow(
      children: [
        ChoiceChip(
          key: const Key('tx-period-months'),
          label: const Text('Mois par mois'),
          selected: range == null,
          onSelected: (_) => ctrl.clear(),
        ),
        ChoiceChip(
          key: const Key('tx-period-custom'),
          label: Text(range == null ? 'Période personnalisée' : '${_d(range.start)} – ${_d(range.end)}'),
          selected: range != null,
          onSelected: (_) async {
            final picked = await _pickRange(context, range);
            if (picked == null || !context.mounted) return;
            _applyRange(context, () => ctrl.set(picked.start, picked.end));
          },
        ),
      ],
    );
  }
}

/// Rangée de puces défilant horizontalement.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (i, c) in children.indexed)
          Padding(
            padding: EdgeInsets.only(right: i == children.length - 1 ? 0 : 8),
            child: c,
          ),
      ],
    ),
  );
}
