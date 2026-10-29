import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/operation.dart';
import 'package:konekt/core/domain/service_type.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/features/payment/domain/payment_models.dart';
import 'package:konekt/features/payment/domain/service_config.dart';
import 'package:konekt/features/payment/presentation/providers/payment_flow.dart';

import '../../helpers/test_app.dart';
import 'payment_test_utils.dart';

/// Le serveur traite la requête, mais la réponse n'arrive pas telle quelle au téléphone.
class _LoseResponse extends Interceptor {
  _LoseResponse(this.path, this.replace);
  final String path;

  /// Réponse de remplacement (null = coupure réseau).
  final Response<dynamic>? Function(RequestOptions o)? replace;
  int remaining = 1;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (remaining > 0 && response.requestOptions.path == path) {
      remaining--;
      final o = response.requestOptions;
      final r = replace?.call(o);
      handler.reject(
        r == null
            ? DioException(requestOptions: o, type: DioExceptionType.connectionError)
            : DioException.badResponse(statusCode: r.statusCode!, requestOptions: o, response: r),
        true,
      );
      return;
    }
    handler.next(response);
  }
}

Response<dynamic> _error(RequestOptions o, int status, String code, String message) => Response<dynamic>(
  requestOptions: o,
  statusCode: status,
  data: {'statusCode': status, 'code': code, 'message': message, 'requestId': 'req_TEST'},
);

void main() {
  late ClockDb db;
  late ProviderContainer container;
  PaymentFlowController flow() => container.read(paymentFlowProvider.notifier);
  PaymentFlowState state() => container.read(paymentFlowProvider);

  Future<void> setUpEnv() async {
    db = ClockDb(hasPin: true);
    final env = await TestEnv.create(signedIn: true, db: db);
    container = ProviderContainer(
      overrides: [...env.overrides, paymentClockProvider.overrideWithValue(() => db.now())],
    );
    container.listen(paymentFlowProvider, (_, _) {});
    await TestEnv.waitForAuth(container);
  }

  void lose(Response<dynamic>? Function(RequestOptions o)? replace) =>
      container.read(dioProvider).interceptors.add(_LoseResponse('/catalog/confirm', replace));

  int catalogOps(String reference) => db.operations.where((o) => o['idempotencyKey'] == reference).length;

  PaymentRequest data() {
    final config = serviceConfig(ServiceType.data);
    const s = FormSelection(
      product: MobileProduct(id: '18490', name: '5 Go', priceType: 'FIXED', price: 3000),
      productsLoaded: true,
    );
    final values = {'beneficiary': '0196666262', 'productId': '18490'};
    return buildRequest(config, values, s, cardCustomerId: db.sessionCardId);
  }

  setUp(setUpEnv);
  tearDown(() => container.dispose());

  test('réponse perdue puis devis expiré : même référence renvoyée, aucun second paiement', () async {
    await flow().requestQuote(data());
    final reference = state().reference!;
    final opsBefore = db.operations.length;
    lose(null);

    expect(await flow().submitSecret('482915'), SecretOutcome.retry);
    expect(state().confirmSent, isTrue);
    expect(catalogOps(reference), 1, reason: 'le serveur a bien exécuté le premier envoi');

    db.advance(const Duration(minutes: 9, seconds: 30)); // devis désormais trop ancien
    expect(await flow().submitSecret('482915'), SecretOutcome.submitted);
    expect(state().reference, reference, reason: 'jamais de nouvelle référence');
    expect(await flow().requote(), isFalse, reason: 'nouveau devis interdit après un envoi incertain');
    expect(db.operations.length, opsBefore + 1, reason: 'un seul paiement');
  });

  test('« déjà en cours de traitement » : on suit l’opération retrouvée par sa référence', () async {
    await flow().requestQuote(data());
    final reference = state().reference!;
    lose(
      (o) => _error(
        o,
        400,
        'REQUEST_REJECTED',
        'Une vente portant la référence « $reference » est déjà en cours de traitement.',
      ),
    );

    expect(await flow().submitSecret('482915'), SecretOutcome.submitted);
    expect(state().review, isNotNull);
    expect(state().needsRequote, isFalse);
    expect(state().canSearchOperation, isTrue);

    final op = await flow().refreshOperation();
    expect(op, isNotNull);
    expect(op!.status, OperationStatus.success);
    expect(state().operationId, op.id);
    expect(catalogOps(reference), 1);
  });

  test('erreur 500 sur la confirmation du catalogue : opération retrouvée et suivie', () async {
    await flow().requestQuote(data());
    final reference = state().reference!;
    lose((o) => _error(o, 500, 'INTERNAL_ERROR', 'Sort incertain. NE LA RELANCEZ PAS.'));

    expect(await flow().submitSecret('482915'), SecretOutcome.submitted);
    expect(state().operationId, isNull);
    final op = await flow().refreshOperation();
    expect(op?.status, OperationStatus.success);
    expect(state().operationId, isNotNull);
    expect(catalogOps(reference), 1);
  });

  test('refus après un envoi incertain : suivi plutôt que nouveau devis', () async {
    await flow().requestQuote(data());
    lose(null);
    expect(await flow().submitSecret('482915'), SecretOutcome.retry);
    // Le second envoi reçoit un refus (ex. devis consommé par le premier envoi).
    lose((o) => _error(o, 400, 'REQUEST_REJECTED', 'Ce devis a déjà été utilisé.'));
    expect(await flow().submitSecret('482915'), SecretOutcome.submitted);
    expect(state().needsRequote, isFalse);
    expect(state().review, isNotNull);
  });
}
