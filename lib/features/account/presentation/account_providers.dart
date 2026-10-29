import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/app_notification.dart';
import '../../../core/domain/card.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/session.dart';
import '../../../core/domain/transaction.dart';
import '../../../core/storage/app_prefs.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../data/account_repository.dart';

/// Rattache un provider à la session : il est recalculé (et ses données d'une autre session oubliées)
/// à chaque connexion, déconnexion ou changement de carte.
void watchSession(Ref ref) => ref.watch(cardSessionProvider.select((s) => s?.cardCustomerId));

/// Identifiant de la carte de session (exception si non connecté).
String requireCardId(Ref ref) {
  final s = ref.watch(cardSessionProvider);
  if (s == null) throw StateError('Aucune session porteur.');
  return s.cardCustomerId;
}

/// Carte de session (`GET /cards`, ou `details` pour une carte externe).
/// Mettre à jour via [CardController.setStatus] après une action de statut.
final cardProvider = AsyncNotifierProvider<CardController, CardInfo>(CardController.new);

class CardController extends AsyncNotifier<CardInfo> {
  @override
  Future<CardInfo> build() => ref.watch(accountRepositoryProvider).card(requireCardId(ref));

  void setStatus(CardStatus status) {
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(status: status));
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(accountRepositoryProvider).card(requireCardId(ref)));
  }
}

/// Statut courant de la carte (null tant qu'il n'est pas chargé).
final cardStatusProvider = Provider<CardStatus?>((ref) => ref.watch(cardProvider).value?.status);

/// Titulaire : nom issu de la session, coordonnées de la fiche carte quand elle est chargée.
final holderProvider = Provider<Holder?>((ref) {
  final CardSession? s = ref.watch(cardSessionProvider);
  if (s == null) return null;
  final card = ref.watch(cardProvider).value;
  return Holder(firstName: s.firstName, lastName: s.lastName, email: card?.email, phone: card?.phone);
});

/// Solde lu en direct chez l'émetteur. Carte suspendue/bloquée → erreur 400 (solde non lisible).
/// `ref.invalidate(balanceProvider)` après chaque opération.
final balanceProvider = FutureProvider<num>((ref) => ref.watch(accountRepositoryProvider).balance(requireCardId(ref)));

/// Solde masqué (persisté).
final hideBalanceProvider = NotifierProvider<HideBalance, bool>(HideBalance.new);

class HideBalance extends Notifier<bool> {
  @override
  bool build() => ref.watch(appPrefsProvider).hideBalance;
  void toggle() {
    state = !state;
    ref.read(appPrefsProvider).setHideBalance(state);
  }
}

/// Derniers mouvements du relevé émetteur (accueil). L'historique complet charge ses propres périodes.
final recentTransactionsProvider = FutureProvider<List<CardTransaction>>((ref) async {
  final all = await ref.watch(accountRepositoryProvider).transactions(requireCardId(ref));
  return all.take(4).toList();
});

/// Boîte de messages paginée (`GET /notifications`, `limit` [NotificationsController.pageSize]).
final notificationsProvider = AsyncNotifierProvider<NotificationsController, NotificationsState>(
  NotificationsController.new,
);

/// Messages chargés + pagination + filtre « Non lues ». [unreadCount] vient de la réponse
/// (`unreadCount`, indépendant des filtres) : c'est la pastille.
class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.nextCursor,
    this.unreadCount = 0,
    this.unreadOnly = false,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<AppNotification> items;

  /// Page suivante ; null = tout est chargé.
  final String? nextCursor;
  final int unreadCount;
  final bool unreadOnly;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;

  NotificationsState copyWith({
    List<AppNotification>? items,
    int? unreadCount,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearError = false,
  }) => NotificationsState(
    items: items ?? this.items,
    nextCursor: nextCursor,
    unreadCount: unreadCount ?? this.unreadCount,
    unreadOnly: unreadOnly,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

class NotificationsController extends AsyncNotifier<NotificationsState> {
  static const pageSize = 20;

  bool _unreadOnly = false;

  /// Filtre « Non lues » demandé (y compris pendant le chargement de la première page).
  bool get unreadOnly => _unreadOnly;

  @override
  Future<NotificationsState> build() async {
    watchSession(ref);
    return _firstPage();
  }

  Future<NotificationsState> _firstPage() async {
    final page = await ref.read(accountRepositoryProvider).notifications(limit: pageSize, unreadOnly: _unreadOnly);
    return NotificationsState(
      items: page.items,
      nextCursor: page.nextCursor,
      unreadCount: page.unreadCount,
      unreadOnly: _unreadOnly,
    );
  }

  /// Filtre « Non lues » (`unreadOnly`) : recharge la première page.
  Future<void> setUnreadOnly(bool value) async {
    if (value == _unreadOnly && state.hasValue) return;
    _unreadOnly = value;
    state = const AsyncLoading<NotificationsState>();
    state = await AsyncValue.guard(_firstPage);
  }

  /// Page suivante (défilement ou « Voir plus »).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final page = await ref
          .read(accountRepositoryProvider)
          .notifications(cursor: current.nextCursor, limit: pageSize, unreadOnly: current.unreadOnly);
      final latest = state.value ?? current;
      // Un message rangé entre-temps décale les pages : on ignore les doublons.
      final known = {for (final n in latest.items) n.id};
      state = AsyncData(
        NotificationsState(
          items: [...latest.items, ...page.items.where((n) => !known.contains(n.id))],
          nextCursor: page.nextCursor,
          unreadCount: page.unreadCount,
          unreadOnly: current.unreadOnly,
        ),
      );
    } catch (e) {
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(loadingMore: false, loadMoreError: e));
    }
  }

  Future<void> markRead(String id) async {
    final current = state.value;
    if (current != null) {
      final wasUnread = current.items.any((n) => n.id == id && !n.read);
      state = AsyncData(
        current.copyWith(
          items: [for (final n in current.items) n.id == id ? n.markRead() : n],
          unreadCount: wasUnread && current.unreadCount > 0 ? current.unreadCount - 1 : current.unreadCount,
        ),
      );
    }
    await ref.read(accountRepositoryProvider).markNotificationRead(id);
    ref.invalidate(unreadCountProvider);
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(items: [for (final n in current.items) n.markRead()], unreadCount: 0));
    }
    await ref.read(accountRepositoryProvider).markAllNotificationsRead();
    ref.invalidate(unreadCountProvider);
  }

  /// Range un message (`DELETE /notifications/:id`) : retiré tout de suite de la liste, remis en cas d'échec.
  Future<void> archive(String id) async {
    final current = state.value;
    final index = current?.items.indexWhere((n) => n.id == id) ?? -1;
    if (current != null && index >= 0) {
      final removed = current.items[index];
      state = AsyncData(
        current.copyWith(
          items: [...current.items]..removeAt(index),
          unreadCount: !removed.read && current.unreadCount > 0 ? current.unreadCount - 1 : current.unreadCount,
        ),
      );
    }
    try {
      await ref.read(accountRepositoryProvider).archiveNotification(id);
    } catch (_) {
      final latest = state.value;
      if (current != null && index >= 0 && latest != null) {
        final items = [...latest.items]..insert(index.clamp(0, latest.items.length), current.items[index]);
        state = AsyncData(latest.copyWith(items: items, unreadCount: current.unreadCount));
      }
      rethrow;
    } finally {
      ref.invalidate(unreadCountProvider);
    }
  }

  /// Pull-to-refresh : recharge la première page (filtre conservé).
  Future<void> refresh() async {
    state = await AsyncValue.guard(_firstPage);
    ref.invalidate(unreadCountProvider);
  }
}

/// Pastille de notifications : `GET /notifications/unread-count`, rafraîchie toutes les minutes
/// (le push n'est pas encore branché côté API).
final unreadCountProvider = FutureProvider<int>((ref) async {
  watchSession(ref);
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    return await ref.watch(accountRepositoryProvider).unreadCount();
  } catch (_) {
    return 0;
  }
});

/// Publicités d'un emplacement, triées par priorité, sans celles masquées.
/// ⚠️ Hors API CardConnect v2 : en cas d'erreur (route absente), aucune publicité.
final promotionsProvider = FutureProvider.family<List<Promotion>, PromoPlacement>((ref, placement) async {
  watchSession(ref);
  final dismissed = ref.watch(dismissedPromosProvider);
  try {
    final items = await ref.watch(accountRepositoryProvider).promotions(placement);
    return items.where((p) => !dismissed.contains(p.id)).toList()..sort((a, b) => a.priority.compareTo(b.priority));
  } catch (_) {
    return const [];
  }
});

final dismissedPromosProvider = NotifierProvider<DismissedPromos, List<String>>(DismissedPromos.new);

class DismissedPromos extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(appPrefsProvider).dismissedPromos;
  void dismiss(String id) {
    state = [...state, id];
    ref.read(appPrefsProvider).setDismissedPromos(state);
  }
}

/// État de la plateforme (`GET /status`, public). Erreur → pas de bannière.
final platformStatusProvider = FutureProvider<PlatformStatus?>((ref) async {
  try {
    return await ref.watch(accountRepositoryProvider).status();
  } catch (_) {
    return null;
  }
});

/// Services ouverts/grisés pour ce porteur (`GET /catalog/services`). À recharger à l'ouverture
/// de chaque parcours. Erreur → liste vide (aucune tuile grisée par défaut).
final serviceOffersProvider = FutureProvider<List<ServiceOffer>>((ref) async {
  watchSession(ref);
  try {
    return await ref.watch(accountRepositoryProvider).services();
  } catch (_) {
    return const [];
  }
});

/// Rafraîchit ce qui dépend d'une opération (solde, mouvements, notifications, carte).
void refreshAccountFromWidget(WidgetRef ref) {
  ref
    ..invalidate(balanceProvider)
    ..invalidate(recentTransactionsProvider)
    ..invalidate(notificationsProvider)
    ..invalidate(unreadCountProvider);
}
