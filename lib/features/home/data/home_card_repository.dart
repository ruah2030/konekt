import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';

/// Actions de statut déclenchées depuis l'accueil (alerte « Réactiver ma carte »).
class HomeCardRepository {
  HomeCardRepository(this._dio);
  final Dio _dio;

  /// `PATCH /cards/status` `{cardCustomerId, newStatus: 'Active'}` (guide Partie 4 §13).
  /// Aucun PIN exigé par l'API : la confirmation se fait dans l'app.
  Future<Result<void>> reactivate(String cardCustomerId) => Result.guard(
    () => _dio.patch<void>('/cards/status', data: {'cardCustomerId': cardCustomerId, 'newStatus': 'Active'}),
  );
}

final homeCardRepositoryProvider = Provider<HomeCardRepository>((ref) => HomeCardRepository(ref.watch(dioProvider)));
