import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/promotion.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/presentation/account_providers.dart';
import '../../../promotions/presentation/promo_slot.dart';
import '../widgets/home_sections.dart';
import '../widgets/home_top_section.dart';

/// Onglet Accueil : solde, actions rapides, publicités, catalogue et derniers mouvements.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(cardProvider)
      ..invalidate(balanceProvider)
      ..invalidate(recentTransactionsProvider)
      ..invalidate(unreadCountProvider)
      ..invalidate(platformStatusProvider)
      ..invalidate(serviceOffersProvider);
    await Future.wait<Object?>([
      ref.read(cardProvider.future),
      ref.read(balanceProvider.future),
      ref.read(recentTransactionsProvider.future),
    ]).catchError((_) => const <Object?>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: KColors.background,
        body: RefreshIndicator(
          key: const Key('home-refresh'),
          onRefresh: () => _refresh(ref),
          child: ListView(
            key: const Key('home-list'),
            padding: EdgeInsets.zero,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const HomeTopSection(),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: KColors.background,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HomeIncidents(),
                      CardStatusAlert(),
                      _HomePromos(),
                      ServiceCatalog(),
                      SizedBox(height: 24),
                      RecentTransactions(),
                      SizedBox(height: 24),
                      PoweredBy(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePromos extends ConsumerWidget {
  const _HomePromos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(dismissedPromosProvider);
    final promos = ref.watch(promotionsProvider(PromoPlacement.home)).value ?? const [];
    if (promos.every((p) => dismissed.contains(p.id))) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(bottom: 24),
      child: PromoSlot(placement: PromoPlacement.home, key: Key('home-promos')),
    );
  }
}
