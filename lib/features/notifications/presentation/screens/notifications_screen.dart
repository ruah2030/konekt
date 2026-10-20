import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/domain/app_notification.dart';
import '../../../../core/utils/relative_date.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';

/// Liste des notifications : non lues mises en avant (fond blanc, point orange), tap = lu.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  void _back(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      Navigator.of(context).maybePop();
    } else if (router.canPop()) {
      router.pop();
    } else {
      router.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(notificationsProvider);
    final Widget body;
    if (notifs.hasValue) {
      final items = notifs.value!;
      body = items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                EmptyState(
                  key: Key('notifs-empty'),
                  message: "Aucune notification pour l'instant.",
                  icon: Symbols.notifications_rounded,
                ),
              ],
            )
          : ListView.separated(
              key: const Key('notifs-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => NotificationTile(
                items[i],
                onTap: items[i].read ? null : () => ref.read(notificationsProvider.notifier).markRead(items[i].id),
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
    return Scaffold(
      backgroundColor: KColors.background,
      appBar: AppBar(
        backgroundColor: KColors.background,
        leading: IconButton(
          key: const Key('notifs-back'),
          tooltip: 'Retour',
          onPressed: () => _back(context),
          icon: const Icon(Symbols.arrow_back_rounded, color: KColors.primary),
        ),
        title: const Text('Notifications'),
        actions: [
          IconButton(
            key: const Key('notifs-read-all'),
            tooltip: 'Tout marquer comme lu',
            onPressed: notifs.hasValue ? () => ref.read(notificationsProvider.notifier).markAllRead() : null,
            icon: const Icon(Symbols.done_all_rounded, color: KColors.primary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        key: const Key('notifs-refresh'),
        onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
        child: body,
      ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile(this.notification, {this.onTap, super.key});
  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.read;
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
                  key: Key('notif-dot-${n.id}'),
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: unread ? KColors.warning : const Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KColors.primary),
                      ),
                      const SizedBox(height: 4),
                      Text(n.body, style: const TextStyle(fontSize: 14, height: 1.43, color: Color(0xFF475569))),
                      const SizedBox(height: 4),
                      Text(
                        relativeDate(n.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: KColors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
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
