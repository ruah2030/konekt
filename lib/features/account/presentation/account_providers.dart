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

final notificationsProvider = AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    watchSession(ref);
    return (await ref.watch(accountRepositoryProvider).notifications(limit: 50)).items;
  }

  Future<void> markRead(String id) async {
    final list = state.value ?? const [];
    state = AsyncData([for (final n in list) n.id == id ? n.markRead() : n]);
    await ref.read(accountRepositoryProvider).markNotificationRead(id);
    ref.invalidate(unreadCountProvider);
  }

  Future<void> markAllRead() async {
    final list = state.value ?? const [];
    state = AsyncData([for (final n in list) n.markRead()]);
    await ref.read(accountRepositoryProvider).markAllNotificationsRead();
    ref.invalidate(unreadCountProvider);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () async => (await ref.read(accountRepositoryProvider).notifications(limit: 50)).items,
    );
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
