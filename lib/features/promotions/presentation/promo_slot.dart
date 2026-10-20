import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/promotion.dart';
import '../../../design_system/design_system.dart';
import '../../account/presentation/account_providers.dart';
import 'promo_actions.dart';
import 'widgets/home_promo_card.dart';

/// Emplacement publicitaire. Ne rend rien s'il n'y a aucune publicité (vide, chargement ou erreur).
///
/// - [PromoPlacement.home] : carrousel à rotation automatique avec points indicateurs ;
/// - autres emplacements : première publicité en [PromoCard].
class PromoSlot extends ConsumerWidget {
  const PromoSlot({required this.placement, super.key});
  final PromoPlacement placement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(dismissedPromosProvider);
    final promos = (ref.watch(promotionsProvider(placement)).value ?? const <Promotion>[])
        .where((p) => !dismissed.contains(p.id))
        .toList();
    if (promos.isEmpty) return const SizedBox.shrink();
    if (placement == PromoPlacement.home) return PromoCarousel(promos: promos);
    final promo = promos.first;
    return PromoCard(
      key: Key('promo-${promo.id}'),
      promo: promo,
      onTap: () => openPromotion(context, ref, promo),
      onDismiss: () => dismissPromotion(ref, promo),
    );
  }
}

/// Carrousel de l'accueil : une publicité à la fois, rotation toutes les [interval], balayage horizontal.
class PromoCarousel extends ConsumerStatefulWidget {
  const PromoCarousel({required this.promos, this.interval = const Duration(seconds: 5), super.key});
  final List<Promotion> promos;
  final Duration interval;

  @override
  ConsumerState<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends ConsumerState<PromoCarousel> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted && widget.promos.length > 1) setState(() => _index++);
    });
  }

  void _goTo(int i) {
    setState(() => _index = i);
    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    final promos = widget.promos;
    final current = _index % promos.length;
    final promo = promos[current];
    return Column(
      key: const Key('promo-carousel'),
      children: [
        GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 100 || promos.length < 2) return;
            _goTo((current + (v < 0 ? 1 : promos.length - 1)) % promos.length);
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            layoutBuilder: (currentChild, previous) =>
                Stack(alignment: Alignment.topCenter, children: [...previous, ?currentChild]),
            child: HomePromoCard(
              key: ValueKey(promo.id),
              promo: promo,
              onTap: () => openPromotion(context, ref, promo),
              onDismiss: () => dismissPromotion(ref, promo),
            ),
          ),
        ),
        if (promos.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var k = 0; k < promos.length; k++)
                Semantics(
                  button: true,
                  label: 'Annonce ${k + 1} sur ${promos.length}',
                  child: GestureDetector(
                    key: Key('promo-dot-$k'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _goTo(k),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: k == current ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: k == current ? KColors.primary : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
