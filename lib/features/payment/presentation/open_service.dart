import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/domain/card.dart';
import '../../../core/domain/service_type.dart';
import '../../../design_system/widgets/feedback.dart';
import '../../account/presentation/account_providers.dart';

/// Point d'entrée unique vers un service (accueil, catalogue, publicités, carte).
/// Refuse si la carte n'est pas active ou si le service est indisponible.
void openService(BuildContext context, WidgetRef ref, ServiceType type) {
  final status = ref.read(cardStatusProvider);
  if (status != null && status != CardStatus.active) {
    showToast(context, status.blockedMessage);
    return;
  }
  if (type == ServiceType.tv) {
    showToast(context, 'Abonnement TV momentanément indisponible. Réessayez plus tard.');
    return;
  }
  context.push(Routes.service(type));
}
