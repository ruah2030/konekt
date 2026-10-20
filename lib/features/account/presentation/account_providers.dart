import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/app_notification.dart';
import '../../../core/domain/card.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/transaction.dart';
import '../../../core/storage/app_prefs.dart';
import '../data/account_repository.dart';

/// Titulaire de la carte connectée.
final holderProvider = FutureProvider<Holder>((ref) => ref.watch(accountRepositoryProvider).me());

/// Carte de la session. Mettre à jour via [CardController.setStatus] après une action de statut.
final cardProvider = AsyncNotifierProvider<CardController, CardInfo>(CardController.new);

class CardController extends AsyncNotifier<CardInfo> {
  @override
  Future<CardInfo> build() => ref.watch(accountRepositoryProvider).card();

  void setStatus(CardStatus status) {
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(status: status));
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(accountRepositoryProvider).card());
  }
}

/// Statut courant de la carte (actif par défaut tant qu'il n'est pas chargé).
final cardStatusProvider = Provider<CardStatus?>((ref) => ref.watch(cardProvider).value?.status);

/// Solde disponible en FCFA. `ref.invalidate(balanceProvider)` après chaque opération.
final balanceProvider = FutureProvider<int>((ref) => ref.watch(accountRepositoryProvider).balance());

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

/// Premiers mouvements (accueil). L'historique complet pagine lui-même.
final recentTransactionsProvider = FutureProvider<List<CardTransaction>>(
  (ref) async => (await ref.watch(accountRepositoryProvider).transactions(limit: 4)).items,
);

final notificationsProvider = AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() => ref.watch(accountRepositoryProvider).notifications();

  Future<void> markRead(String id) async {
    final list = state.value ?? const [];
    state = AsyncData([for (final n in list) n.id == id ? n.markRead() : n]);
    await ref.read(accountRepositoryProvider).markNotificationRead(id);
  }

  Future<void> markAllRead() async {
    final list = state.value ?? const [];
    state = AsyncData([for (final n in list) n.markRead()]);
    await ref.read(accountRepositoryProvider).markAllNotificationsRead();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(accountRepositoryProvider).notifications());
  }
}

final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).value?.where((n) => !n.read).length ?? 0,
);

/// Publicités d'un emplacement, triées par priorité, sans celles masquées par l'utilisateur.
final promotionsProvider = FutureProvider.family<List<Promotion>, PromoPlacement>((ref, placement) async {
  final dismissed = ref.watch(dismissedPromosProvider);
  final items = await ref.watch(accountRepositoryProvider).promotions(placement);
  return items.where((p) => !dismissed.contains(p.id)).toList()..sort((a, b) => a.priority.compareTo(b.priority));
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

/// Incidents opérateurs en cours (bannière login + accueil). Erreur → aucune bannière.
final incidentsProvider = FutureProvider<List<SystemIncident>>((ref) async {
  try {
    return await ref.watch(accountRepositoryProvider).incidents();
  } catch (_) {
    return const [];
  }
});

/// Rafraîchit tout ce qui dépend d'une opération (solde, mouvements, notifications, carte).
void refreshAccount(Ref ref) {
  ref
    ..invalidate(balanceProvider)
    ..invalidate(recentTransactionsProvider)
    ..invalidate(notificationsProvider);
}

/// Variante utilisable depuis un widget.
void refreshAccountFromWidget(WidgetRef ref) {
  ref
    ..invalidate(balanceProvider)
    ..invalidate(recentTransactionsProvider)
    ..invalidate(notificationsProvider);
}

/// Vide les caches liés à la session (déconnexion / changement de carte).
void resetAccountState(Ref ref) {
  ref
    ..invalidate(holderProvider)
    ..invalidate(cardProvider)
    ..invalidate(balanceProvider)
    ..invalidate(recentTransactionsProvider)
    ..invalidate(notificationsProvider)
    ..invalidate(promotionsProvider);
}
