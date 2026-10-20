import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/card.dart';
import '../../../core/network/dio_client.dart';
import '../domain/sensitive_card_data.dart';

/// Actions sur le statut de la carte et affichage sécurisé des données sensibles.
class CardRepository {
  CardRepository(this._dio);
  final Dio _dio;

  Future<CardInfo> _post(String path) async => CardInfo.fromJson((await _dio.post<Map<String, dynamic>>(path)).data!);

  /// ACTIVE → INACTIVE (réversible).
  Future<CardInfo> suspend() => _post('/v1/card/suspend');

  /// INACTIVE → ACTIVE.
  Future<CardInfo> reactivate() => _post('/v1/card/reactivate');

  /// → LOST_OR_STOLEN (définitif). Une alerte est envoyée sur tous les canaux.
  Future<CardInfo> declareLost() => _post('/v1/card/lost');

  /// Numéro, expiration et CVV, valables 60 s (403 FORBIDDEN si la carte n'est pas active).
  ///
  /// SÉCURITÉ : en production, cet affichage doit idéalement passer par la page ou le SDK
  /// sécurisé de l'émetteur (jeton/URL à usage unique rendu par l'émetteur), afin que le PAN et
  /// le CVV ne transitent pas par nos serveurs. Dans tous les cas, ces données ne sont jamais
  /// stockées (ni prefs, ni cache, ni disque) ni journalisées (pas de log réseau des réponses).
  Future<SensitiveCardData> sensitiveDisplay() async {
    final res = await _dio.post<Map<String, dynamic>>('/v1/card/sensitive-display');
    return SensitiveCardData.fromJson(res.data!);
  }
}

final cardRepositoryProvider = Provider<CardRepository>((ref) => CardRepository(ref.watch(dioProvider)));
