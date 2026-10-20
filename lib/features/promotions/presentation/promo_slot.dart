import 'package:flutter/material.dart';

import '../../../core/domain/promotion.dart';

// TODO(agent B): implémentation réelle (carrousel pour `home`, carte unique sinon).
/// Emplacement publicitaire. Ne rend rien s'il n'y a aucune publicité.
class PromoSlot extends StatelessWidget {
  const PromoSlot({required this.placement, super.key});
  final PromoPlacement placement;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
