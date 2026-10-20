import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/promotion.dart';
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
                note: "Relevé lu en direct chez l'émetteur, sur le dernier mois.",
                emptyMessage: 'Aucun mouvement pour le moment.',
                tileBuilder: (context, tx, divider) => TransactionTile(tx, showDivider: divider),
              ),
              _HistoryTab(
                storageKey: 'history-ops',
                provider: operationsHistoryProvider,
                note: 'Paiements lancés depuis Konekt avec leur statut. Touchez pour voir le reçu.',
                emptyMessage: 'Aucune opération pour le moment.',
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
  });

  final String storageKey;
  final AsyncNotifierProvider<PagedController<T>, PagedList<T>> provider;
  final String note;
  final String emptyMessage;
  final Widget Function(BuildContext context, T item, bool showDivider) tileBuilder;

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
        section(ErrorView(error: async.error!, onRetry: () => ref.invalidate(provider)))
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
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400 && list != null && list.hasMore && list.loadMoreError == null) {
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
