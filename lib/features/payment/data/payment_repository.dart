import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/json.dart';
import '../../../core/domain/operation.dart';
import '../../../core/domain/service_type.dart';
import '../../../core/network/dio_client.dart';
import '../domain/payment_models.dart';

/// Paiements : sorties d'argent par carte (guide Partie 4 §6-§12), catalogue (Partie 5),
/// portefeuilles externes (Partie 6 §3.1).
///
/// Retrait vers Mobile Money : voie « cards » (`POST /cards/to-mobile-money/initiate` puis
/// `execute`/`confirm`), et non `/external-wallets/payout/quote` — une seule voie, comme le
/// recommande le guide (Partie 3, écran 10) : même parcours PIN/OTP que le transfert.
class PaymentRepository {
  PaymentRepository(this._dio);
  final Dio _dio;

  Future<Json> _get(String path, [Map<String, dynamic>? query]) async =>
      (await _dio.get<Map<String, dynamic>>(path, queryParameters: query)).data!;

  Future<Json> _post(String path, [Object? body]) async =>
      (await _dio.post<Map<String, dynamic>>(path, data: body)).data!;

  /// `GET /external-wallets/channels?country=BJ&operation=…` (`PAYOUT` | `COLLECT`).
  Future<List<WalletChannel>> channels({required String operation}) async {
    final j = await _get('/external-wallets/channels', {'country': 'BJ', 'operation': operation});
    return j.list('data').map(WalletChannel.fromJson).toList();
  }

  /// `GET /catalog/lookup/mobile/:msisdn/products?type=TOPUP|DATA`.
  Future<List<MobileProduct>> mobileProducts(String msisdn, String type) async {
    final j = await _get('/catalog/lookup/mobile/${Uri.encodeComponent(msisdn)}/products', {'type': type});
    return j.list('data').map(MobileProduct.fromJson).toList();
  }

  /// `POST /catalog/quote`. Un refus est un 200 avec `feasible:false` (à tester).
  Future<PaymentQuote> catalogQuote(PaymentRequest r) async {
    final j = await _post('/catalog/quote', {'service': r.service.apiKey, 'funding': r.funding, 'input': r.input});
    return PaymentQuote.fromCatalog(j, service: r.service, path: r.path);
  }

  /// `POST /catalog/confirm`. [reference] : UUID v4 de la tentative (idempotence) ; [pin] si carte.
  Future<ExecutionResult> catalogConfirm({
    required PaymentRequest request,
    required String quoteId,
    required String reference,
    String? pin,
  }) async => ExecutionResult.fromJson(
    await _post('/catalog/confirm', {
      'quoteId': quoteId,
      'service': request.service.apiKey,
      'funding': request.funding,
      'reference': reference,
      'pin': ?pin,
    }),
  );

  /// `POST /commerce/operations/:id/funding/confirm` (code B-MO, 4 à 8 chiffres).
  Future<ExecutionResult> fundingConfirm(String operationId, String code) async =>
      ExecutionResult.fromJson(await _post('/commerce/operations/$operationId/funding/confirm', {'code': code}));

  /// `POST /commerce/operations/:id/funding/cancel`. Toujours lire `status` (peut être `SUCCESS`).
  Future<ExecutionResult> fundingCancel(String operationId) async =>
      ExecutionResult.fromJson(await _post('/commerce/operations/$operationId/funding/cancel'));

  /// `POST /cards/transfer/initiate` ou `/cards/to-mobile-money/initiate` selon [request].
  Future<PaymentQuote> initiate(PaymentRequest request, {required String requestId, required DateTime now}) async {
    final path = request.service == ServiceType.transfer
        ? '/cards/transfer/initiate'
        : '/cards/to-mobile-money/initiate';
    final j = await _post(path, {...request.cardBody, 'requestId': requestId});
    return PaymentQuote.fromCardInit(j, service: request.service, now: now);
  }

  /// `POST /cards/operations/:id/execute` (voie PIN).
  Future<ExecutionResult> execute(String operationId, String pin) async =>
      ExecutionResult.fromJson(await _post('/cards/operations/$operationId/execute', {'pin': pin}));

  /// `POST /cards/operations/confirm` (voie OTP).
  Future<ExecutionResult> confirmOtp(String operationId, String code) async =>
      ExecutionResult.fromJson(await _post('/cards/operations/confirm', {'operationId': operationId, 'code': code}));

  /// `DELETE /cards/operations/:id` : abandon d'une opération carte non exécutée.
  Future<void> cancel(String operationId, {String reason = "Abandon par l'utilisateur"}) =>
      _dio.delete<void>('/cards/operations/$operationId', data: {'reason': reason});

  /// `GET /cards/operations/:id` : suivi et reçu (`OperationStatusResponseDto`).
  /// Retrouve l'opération créée par une confirmation du catalogue dont la réponse a été perdue
  /// (`GET /operations?search=<reference>` : la `reference` est conservée dans `idempotencyKey`).
  /// `null` si le serveur ne l'a pas (encore) enregistrée.
  Future<String?> operationIdByReference(String reference) async {
    final j = await _get('/operations', {'search': reference, 'limit': 5});
    for (final o in j.list('data')) {
      if (o['idempotencyKey'] == reference || o['reference'] == reference) return o['id'] as String?;
    }
    return null;
  }

  Future<Operation> operation(String operationId, {String? sessionCardCustomerId}) async =>
      Operation.fromJson(await _get('/cards/operations/$operationId'), sessionCardCustomerId: sessionCardCustomerId);
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) => PaymentRepository(ref.watch(dioProvider)));

/// Portefeuilles proposés (`PAYOUT` pour un retrait, `COLLECT` pour une recharge).
final walletChannelsProvider = FutureProvider.autoDispose.family<List<WalletChannel>, String>(
  (ref, operation) => ref.watch(paymentRepositoryProvider).channels(operation: operation),
);
