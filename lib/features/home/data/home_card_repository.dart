import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';

/// Actions de statut déclenchées depuis l'accueil (alerte « Réactiver ma carte »).
class HomeCardRepository {
  HomeCardRepository(this._dio);
  final Dio _dio;

  /// `POST /v1/card/reactivate`.
  Future<Result<void>> reactivate() => Result.guard(() => _dio.post<void>('/v1/card/reactivate'));
}

final homeCardRepositoryProvider = Provider<HomeCardRepository>((ref) => HomeCardRepository(ref.watch(dioProvider)));
