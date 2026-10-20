import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/domain/promotion.dart';
import '../../../core/domain/service_type.dart';
import '../../../design_system/widgets/feedback.dart';
import '../../account/presentation/account_providers.dart';
import '../../payment/presentation/open_service.dart';

/// Message affiché quand un lien publicitaire ne peut pas être ouvert.
const promoLinkErrorMessage = "Impossible d'ouvrir le lien. Réessayez plus tard.";

/// Ouvre la cible d'une publicité : un service de l'app (`service`) ou un lien externe (`url`).
Future<void> openPromotion(BuildContext context, WidgetRef ref, Promotion promo) async {
  final action = promo.action;
  if (action.isService) {
    final type = ServiceType.tryParse(action.target);
    if (type == null) {
      showToast(context, 'Service momentanément indisponible. Réessayez plus tard.');
      return;
    }
    openService(context, ref, type);
    return;
  }
  final uri = promoUri(action.target);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) showToast(context, promoLinkErrorMessage);
}

/// `jumia.bj` → `https://jumia.bj` ; `null` si la cible n'est pas une URL web exploitable.
Uri? promoUri(String target) {
  final t = target.trim();
  if (t.isEmpty) return null;
  final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(t)?.group(1);
  if (scheme != null && !scheme.contains('.') && !t.contains('://')) return null; // tel:, mailto:…
  final uri = Uri.tryParse(t.contains('://') ? t : 'https://$t');
  if (uri == null || uri.host.isEmpty || !(uri.scheme == 'https' || uri.scheme == 'http')) return null;
  return uri;
}

/// Masque définitivement une publicité (préférence persistée).
void dismissPromotion(WidgetRef ref, Promotion promo) => ref.read(dismissedPromosProvider.notifier).dismiss(promo.id);
