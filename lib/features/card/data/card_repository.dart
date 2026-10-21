import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/card.dart';
import '../../../core/network/dio_client.dart';
import '../domain/card_models.dart';

/// Statut de la carte (`PATCH /cards/status`) et affichage sécurisé (`POST /cards/display/authorize`).
class CardRepository {
  CardRepository(this._dio);
  final Dio _dio;

  /// Suspendre (`Inactive`), réactiver (`Active`) ou déclarer perdue (`LostOrStolen`, définitif).
  ///
  /// `LostOrStolen` exige [acknowledgeIrreversible] = true, envoyé seulement APRÈS avoir averti le porteur.
  /// L'API n'exige ni PIN ni code (point ouvert n°6) : la confirmation se fait dans l'app.
  Future<CardStatusChangeResult> changeStatus(
    String cardCustomerId,
    CardStatus newStatus, {
    bool acknowledgeIrreversible = false,
  }) async {
    assert(
      newStatus == CardStatus.active || newStatus == CardStatus.inactive || newStatus == CardStatus.lostOrStolen,
      'newStatus ∈ Active | Inactive | LostOrStolen',
    );
    final res = await _dio.patch<Map<String, dynamic>>(
      '/cards/status',
      data: {
        'cardCustomerId': cardCustomerId,
        'newStatus': newStatus.api,
        if (acknowledgeIrreversible) 'acknowledgeIrreversible': true,
      },
    );
    return CardStatusChangeResult.fromJson(res.data!);
  }

  /// Adresse d'affichage à usage unique (60 s). À n'appeler QU'au tap sur « Afficher » : chaque appel
  /// compte dans les plafonds journaliers, même si la page n'est jamais ouverte.
  /// En natif, pas de `surface` (sinon contrôle du Referer → 403, point ouvert n°21).
  Future<DisplayAuthorization> authorizeDisplay(String cardCustomerId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/cards/display/authorize',
      data: {'cardCustomerId': cardCustomerId},
    );
    return DisplayAuthorization.fromJson(res.data!);
  }
}

final cardRepositoryProvider = Provider<CardRepository>((ref) => CardRepository(ref.watch(dioProvider)));
