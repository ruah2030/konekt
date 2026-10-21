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
                note: "Relevé lu en direct chez l'émetteur, mois par mois.",
                emptyMessage: 'Aucun mouvement sur cette période.',
                loadMoreLabel: 'Charger le mois précédent',
                autoLoad: false,
                tileBuilder: (context, tx, divider) => TransactionTile(tx, showDivider: divider),
              ),
              _HistoryTab(
                storageKey: 'history-ops',
                provider: operationsHistoryProvider,
                note: 'Paiements lancés depuis Konekt avec leur statut. Touchez pour voir le reçu.',
                emptyMessage: 'Aucune opération pour le moment.',
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
    this.autoLoad = true,
  });

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
      if (list == null && async.hasError)
        section(_ErrorOrStatus(error: async.error!, onRetry: () => ref.invalidate(provider)))
      else if (list == null)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (items.isEmpty)
        section(EmptyState(message: emptyMessage))
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
      if (list != null && list.loadingMore)
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
