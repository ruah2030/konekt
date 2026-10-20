import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/json.dart';
import '../../../core/domain/operation.dart';
import '../../../core/network/dio_client.dart';
import '../domain/payment_models.dart';

/// Devis, forfaits et exécution des paiements.
class PaymentRepository {
  PaymentRepository(this._dio);
  final Dio _dio;

  /// `POST /v1/quotes`. [request] : `service`, `amount`, `planId`, `operator`, `target`,
  /// `msisdn`, `meter`, `deliveryChannel`, `contact` (seuls les champs utiles).
  Future<Quote> requestQuote(Map<String, dynamic> request) async =>
      Quote.fromJson((await _dio.post<Map<String, dynamic>>('/v1/quotes', data: request)).data!);

  Future<List<DataPlan>> dataPlans() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/services/data/plans');
    return res.data!.list('items').map(DataPlan.fromJson).toList();
  }

  /// `POST /v1/operations` avec `Idempotency-Key` = [quoteId] : un rejeu renvoie la même opération.
  Future<Operation> execute({required String quoteId, required String pin}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/operations',
      data: {'quoteId': quoteId, 'pin': pin},
      options: Options(headers: {'Idempotency-Key': quoteId}),
    );
    return Operation.fromJson(res.data!.obj('operation'));
  }

  /// Suivi d'une opération en cours (statut et étape à jour).
  Future<Operation> track(String operationId) async =>
      Operation.fromJson((await _dio.get<Map<String, dynamic>>('/v1/payments/$operationId')).data!);
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) => PaymentRepository(ref.watch(dioProvider)));

/// Forfaits internet proposés dans le formulaire « Forfait internet ».
final dataPlansProvider = FutureProvider.autoDispose<List<DataPlan>>(
  (ref) => ref.watch(paymentRepositoryProvider).dataPlans(),
);
