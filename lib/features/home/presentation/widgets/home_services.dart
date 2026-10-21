import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/service_type.dart';
import '../../../../design_system/design_system.dart';
import '../../../account/data/account_repository.dart';
import '../../../account/presentation/account_providers.dart';
import '../../../payment/presentation/open_service.dart';

/// Offre du catalogue correspondant à [type] (`ServiceType.apiKey` == `ServiceOffer.key`), ou null
/// si le service est absent de la liste (liste vide en cas d'erreur : le service reste ouvrable).
ServiceOffer? offerFor(List<ServiceOffer> offers, ServiceType type) {
  for (final o in offers) {
    if (o.key == type.apiKey) return o;
  }
  return null;
}

/// Disponibilité d'un service selon `GET /catalog/services` (absent = disponible).
bool serviceAvailable(WidgetRef ref, ServiceType type) {
  final offer = offerFor(ref.watch(serviceOffersProvider).value ?? const [], type);
  return offer == null || offer.available;
}

/// Ouvre un service depuis l'accueil. Carte non active → message de statut (via [openService]) ;
/// service grisé dans le catalogue → `unavailableReason` en toast, sans ouvrir le parcours.
void openHomeService(BuildContext context, WidgetRef ref, ServiceType type) {
  final status = ref.read(cardStatusProvider);
  final offer = offerFor(ref.read(serviceOffersProvider).value ?? const [], type);
  if ((status == null || status.isActive) && offer != null && !offer.available) {
    showToast(context, offer.unavailableReason ?? 'Service momentanément indisponible. Réessayez plus tard.');
    // Le catalogue se recharge à chaque tentative : le service peut être revenu entre-temps.
    ref.invalidate(serviceOffersProvider);
    return;
  }
  openService(context, ref, type);
}
