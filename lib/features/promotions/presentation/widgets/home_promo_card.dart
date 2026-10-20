import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/domain/promotion.dart';
import '../../../../design_system/design_system.dart';

/// Grande carte publicitaire du carrousel de l'accueil (rayon 28, halo, CTA).
class HomePromoCard extends StatelessWidget {
  const HomePromoCard({required this.promo, required this.onTap, required this.onDismiss, super.key});
  final Promotion promo;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  Color get _glow => switch (promo.theme) {
    PromoTheme.navy => const Color(0x47F0B23A),
    PromoTheme.gold => const Color(0x59F0B23A),
    PromoTheme.mint => const Color(0x381FA54E),
  };

  @override
  Widget build(BuildContext context) {
    final c = promoColors(promo.theme);
    return Material(
      key: Key('promo-${promo.id}'),
      color: c.bg,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 150),
          child: Stack(
            children: [
              Positioned(
                right: -60,
                top: -60,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [_glow, _glow.withValues(alpha: 0)], stops: const [0, 0.7]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${promo.eyebrow} · ANNONCE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: c.accent,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Transform.translate(
                            offset: const Offset(10, 0),
                            child: IconButton(
                              key: Key('promo-dismiss-${promo.id}'),
                              tooltip: 'Masquer',
                              padding: EdgeInsets.zero,
                              onPressed: onDismiss,
                              icon: Icon(Symbols.close_rounded, color: c.sub, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        promo.title,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: c.fg,
                        ),
                      ),
                    ),
                    if (promo.body.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Text(
                          promo.body,
                          style: TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w500, color: c.sub),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      height: 36,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: c.ctaBg, borderRadius: BorderRadius.circular(100)),
                      child: Text(
                        promo.cta,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ctaFg),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
