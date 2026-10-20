import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/domain/promotion.dart';
import '../theme/app_colors.dart';

({Color bg, Color fg, Color sub, Color accent, Color ctaBg, Color ctaFg}) promoColors(PromoTheme t) => switch (t) {
  PromoTheme.navy => (
    bg: KColors.primary,
    fg: Colors.white,
    sub: const Color(0xFFC9CCF0),
    accent: KColors.secondary,
    ctaBg: Colors.white,
    ctaFg: KColors.primary,
  ),
  PromoTheme.gold => (
    bg: KColors.secondaryContainer,
    fg: KColors.primary,
    sub: const Color(0xFF6B5A2E),
    accent: const Color(0xFF9A5A08),
    ctaBg: KColors.primary,
    ctaFg: Colors.white,
  ),
  PromoTheme.mint => (
    bg: KColors.successContainer,
    fg: const Color(0xFF0E3B22),
    sub: const Color(0xFF3F6B50),
    accent: KColors.successDark,
    ctaBg: const Color(0xFF0E3B22),
    ctaFg: Colors.white,
  ),
};

/// Publicité : sur-titre « · ANNONCE », titre, texte, CTA, fermeture.
class PromoCard extends StatelessWidget {
  const PromoCard({required this.promo, required this.onTap, required this.onDismiss, super.key});
  final Promotion promo;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = promoColors(promo.theme);
    final t = Theme.of(context).textTheme;
    return Material(
      color: c.bg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${promo.eyebrow} · ANNONCE',
                      style: t.labelSmall?.copyWith(color: c.accent, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      promo.title,
                      style: t.titleMedium?.copyWith(color: c.fg, fontWeight: FontWeight.w800),
                    ),
                    if (promo.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(promo.body, style: t.bodySmall?.copyWith(color: c.sub)),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: c.ctaBg, borderRadius: BorderRadius.circular(99)),
                      child: Text(
                        promo.cta,
                        style: t.labelLarge?.copyWith(color: c.ctaFg, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: Key('promo-dismiss-${promo.id}'),
                tooltip: 'Masquer',
                onPressed: onDismiss,
                icon: Icon(Symbols.close_rounded, color: c.sub, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class AppRadius {
  static const card = 16.0;
}
