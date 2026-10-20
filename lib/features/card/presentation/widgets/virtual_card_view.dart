import 'package:flutter/material.dart';

import '../../../../core/domain/card.dart';
import '../../../../design_system/design_system.dart';

/// Dégradé de la carte virtuelle (maquette).
const kCardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1C10A0), KColors.primary, Color(0xFF0B0838)],
  stops: [0, 0.45, 1],
);

/// Visuel de la carte virtuelle : logo, statut, •••• last4, titulaire, VISA.
class VirtualCardView extends StatelessWidget {
  const VirtualCardView({required this.card, super.key});
  final CardInfo card;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.586,
      child: Container(
        key: const Key('virtual-card'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: kCardGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x4D140A72), blurRadius: 32, offset: Offset(0, 12))],
        ),
        child: Stack(
          children: [
            const Positioned(right: -90, bottom: -110, child: _Ring(size: 280, alpha: 0.22)),
            const Positioned(right: -40, bottom: -60, child: _Ring(size: 180, alpha: 0.14)),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset(
                        'assets/images/logo-mark.png',
                        width: 62,
                        errorBuilder: (_, _, _) => const SizedBox(width: 62, height: 24),
                      ),
                      StatusPill.card(card.status, key: const Key('card-status-pill')),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '•••• •••• •••• ${card.last4}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              card.holderName.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD7D9F5),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          Text(
                            card.brand.isEmpty ? 'VISA' : card.brand.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.alpha});
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: KColors.secondary.withValues(alpha: alpha)),
    ),
  );
}
