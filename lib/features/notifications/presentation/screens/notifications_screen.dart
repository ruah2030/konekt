import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/app_notification.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/utils/relative_date.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';

/// Boîte de messages in-app (`GET /notifications`, Partie 6 §2), paginée par 20 (défilement ou
/// « Voir plus ») avec un filtre « Non lues » (`unreadOnly`).
///
/// Tap : marque lu puis, si le message pointe vers une opération, ouvre son reçu. Balayage : « Ranger »
/// (`DELETE /notifications/:id`, le message n'est pas supprimé). Le push n'étant pas branché côté API,
/// la pastille de l'accueil interroge `unread-count` ; ici, elle vient du `unreadCount` de la liste.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationsController get _ctrl => ref.read(notificationsProvider.notifier);

  void _back() {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      Navigator.of(context).maybePop();
    } else if (router.canPop()) {
      router.pop();
    } else {
      router.go(Routes.home);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) unawaitedSafe(_ctrl.markRead(n.id));
    final opId = n.operationId;
    if (opId != null) await context.push(Routes.receipt(opId, fromHistory: true));
  }

  Future<void> _archive(AppNotification n) async {
    try {
      await _ctrl.archive(n.id);
      if (mounted) showToast(context, 'Notification rangée.');
    } catch (e) {
      if (mounted) showToast(context, ApiFailure.from(e).message);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _ctrl.markAllRead();
    } catch (e) {
      if (mounted) showToast(context, ApiFailure.from(e).message);
    }
  }

  bool _onScroll(ScrollNotification n, NotificationsState? s) {
    if (s != null && s.hasMore && !s.loadingMore && s.loadMoreError == null && n.metrics.extentAfter < 300) {
      _ctrl.loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final notifs = ref.watch(notificationsProvider);
    final data = notifs.value;
    final unreadOnly = _ctrl.unreadOnly;
    final Widget body;
    if (notifs.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (data != null) {
      final items = data.items;
      body = items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                EmptyState(
                  key: const Key('notifs-empty'),
                  message: unreadOnly ? 'Aucune notification non lue.' : "Aucune notification pour l'instant.",
                  icon: Symbols.notifications_rounded,
                ),
              ],
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) => _onScroll(n, data),
              child: ListView.separated(
                key: const Key('notifs-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i == items.length) return _Footer(state: data, onMore: _ctrl.loadMore);
                  final n = items[i];
                  return Dismissible(
                    key: Key('notif-dismiss-${n.id}'),
                    direction: DismissDirection.endToStart,
                    background: const _ArchiveBackground(),
                    onDismissed: (_) => _archive(n),
                    child: NotificationTile(n, onTap: () => _open(n)),
                  );
                },
              ),
            );
    } else if (notifs.hasError) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [ErrorView(error: notifs.error!, onRetry: () => ref.invalidate(notificationsProvider))],
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }
    final hasUnread = (data?.unreadCount ?? 0) > 0;
    return Scaffold(
      backgroundColor: KColors.background,
      appBar: AppBar(
        backgroundColor: KColors.background,
        leading: IconButton(
          key: const Key('notifs-back'),
          tooltip: 'Retour',
          onPressed: _back,
          icon: const Icon(Symbols.arrow_back_rounded, color: KColors.primary),
        ),
        title: const Text('Notifications'),
        actions: [
          IconButton(
            key: const Key('notifs-read-all'),
            tooltip: 'Tout marquer comme lu',
            onPressed: hasUnread ? _markAllRead : null,
            icon: const Icon(Symbols.done_all_rounded, color: KColors.primary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                ChoiceChip(
                  key: const Key('notifs-filter-all'),
                  label: const Text('Toutes'),
                  selected: !unreadOnly,
                  onSelected: (_) => _ctrl.setUnreadOnly(false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const Key('notifs-filter-unread'),
                  label: Text(data == null || data.unreadCount == 0 ? 'Non lues' : 'Non lues (${data.unreadCount})'),
                  selected: unreadOnly,
                  onSelected: (_) => _ctrl.setUnreadOnly(true),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(key: const Key('notifs-refresh'), onRefresh: _ctrl.refresh, child: body),
          ),
        ],
      ),
    );
  }
}

/// Bas de liste : chargement, erreur de page suivante ou bouton « Voir plus ».
class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onMore});
  final NotificationsState state;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.loadMoreError != null) return ErrorView(error: state.loadMoreError!, onRetry: onMore);
    if (!state.hasMore) return const SizedBox.shrink();
    return Center(
      child: TextButton(key: const Key('notifs-more'), onPressed: onMore, child: const Text('Voir plus')),
    );
  }
}

/// Lance [f] sans l'attendre, en ignorant son erreur éventuelle (marquage lu anodin).
void unawaitedSafe(Future<void> f) => f.catchError((_) {});

class _ArchiveBackground extends StatelessWidget {
  const _ArchiveBackground();

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(color: KColors.surfaceContainer, borderRadius: BorderRadius.circular(16)),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Symbols.archive_rounded, color: KColors.primary, size: 20),
        SizedBox(width: 8),
        Text(
          'Ranger',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KColors.primary),
        ),
      ],
    ),
  );
}

/// Icône et couleurs d'un message selon son `kind`.
({IconData icon, Color fg, Color bg}) notificationStyle(NotificationKind kind) => switch (kind) {
  NotificationKind.info => (icon: Symbols.info_rounded, fg: KColors.info, bg: KColors.infoContainer),
  NotificationKind.success => (icon: Symbols.check_circle_rounded, fg: KColors.success, bg: KColors.successContainer),
  NotificationKind.warning => (icon: Symbols.warning_rounded, fg: KColors.warningDark, bg: KColors.warningContainer),
  NotificationKind.error => (icon: Symbols.error_rounded, fg: KColors.error, bg: KColors.errorContainer),
  NotificationKind.financial => (
    icon: Symbols.payments_rounded,
    fg: KColors.onSecondaryContainer,
    bg: KColors.secondaryContainer,
  ),
  NotificationKind.security => (icon: Symbols.shield_rounded, fg: KColors.primary, bg: KColors.primaryContainer),
};

class NotificationTile extends StatelessWidget {
  const NotificationTile(this.notification, {this.onTap, super.key});
  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.read;
    final style = notificationStyle(n.kind);
    return Container(
      key: Key('notif-${n.id}'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: unread
            ? const [
                BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
                BoxShadow(color: Color(0x0D140A72), blurRadius: 24, offset: Offset(0, 8)),
              ]
            : null,
      ),
      child: Material(
        color: unread ? KColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  key: Key('notif-kind-${n.kind.name}-${n.id}'),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(style.icon, size: 20, color: style.fg),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KColors.primary),
                            ),
                          ),
                          if (unread)
                            Container(
                              key: Key('notif-dot-${n.id}'),
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 6, left: 8),
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: KColors.warning),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(n.message, style: const TextStyle(fontSize: 14, height: 1.43, color: Color(0xFF475569))),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            relativeDate(n.createdAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: KColors.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (n.operationId != null) ...[
                            const Spacer(),
                            const Text(
                              'Voir le reçu',
                              style: TextStyle(fontSize: 12, color: KColors.tertiary, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
