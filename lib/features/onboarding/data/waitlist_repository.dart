import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/json.dart';
import '../../../core/network/dio_client.dart';

/// Liste d'attente de l'écran « Obtenir une invitation ».
///
/// ⚠️ `POST /waitlist` est HORS API CardConnect v2 : l'API réelle n'a aucune route de liste
/// d'attente. Seul le faux backend la sert (`pin_handlers.dart`). Avec l'API réelle, l'appel
/// échoue (404) et l'écran affiche l'erreur : à rebrancher sur un service dédié le moment venu.
class WaitlistRepository {
  WaitlistRepository(this._dio);
  final Dio _dio;

  /// Inscrit le numéro et renvoie la position sur la liste.
  Future<int> join(String msisdn) async {
    final j = (await _dio.post<Map<String, dynamic>>('/waitlist', data: {'msisdn': msisdn})).data ?? const {};
    return j.intOrNull('position') ?? 0;
  }
}

final waitlistRepositoryProvider = Provider<WaitlistRepository>((ref) => WaitlistRepository(ref.watch(dioProvider)));
