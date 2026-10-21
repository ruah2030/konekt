import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/operation.dart';
import 'package:konekt/core/domain/service_type.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/features/payment/domain/payment_models.dart';
import 'package:konekt/features/payment/domain/service_config.dart';
import 'package:konekt/features/payment/presentation/providers/payment_flow.dart';

import '../../helpers/test_app.dart';
import 'payment_test_utils.dart';

void main() {
  late ClockDb db;
  late ProviderContainer container;
  PaymentFlowController flow() => container.read(paymentFlowProvider.notifier);
  PaymentFlowState state() => container.read(paymentFlowProvider);

  Future<void> setUpEnv({bool hasPin = true}) async {
    db = ClockDb(hasPin: hasPin);
    final env = await TestEnv.create(signedIn: true, db: db);
    container = ProviderContainer(
      overrides: [...env.overrides, paymentClockProvider.overrideWithValue(() => db.now())],
    );
    container.listen(paymentFlowProvider, (_, _) {});
    await TestEnv.waitForAuth(container);
  }

  tearDown(() => container.dispose());

  PaymentRequest request(ServiceType type, Map<String, String> values, [FormSelection s = const FormSelection()]) {
    final config = serviceConfig(type);
    expect(validateForm(config, values, s, sessionCardId: db.sessionCardId), isEmpty);
    return buildRequest(config, values, s, cardCustomerId: db.sessionCardId);
  }

  group('formulaire (fonctions pures)', () {
    setUp(() => setUpEnv());

    test('validations locales et construction de la demande', () {
      final transfer = serviceConfig(ServiceType.transfer);
      expect(validateForm(transfer, {}, const FormSelection()), {
        'toCardCustomerId': 'Carte du bénéficiaire : champ obligatoire.',
        'amount': 'Montant (FCFA) : champ obligatoire.',
      });
      expect(validateForm(transfer, {'toCardCustomerId': '1214364O4', 'amount': '50'}, const FormSelection()), {
        'toCardCustomerId': 'Chiffres uniquement : vérifiez qu’aucune lettre « O » n’a été saisie à la place du zéro.',
        'amount': 'Montant minimum : ${formatFcfa(100)}.',
      });
      expect(
        validateForm(
          transfer,
          {'toCardCustomerId': db.sessionCardId, 'amount': '1000'},
          const FormSelection(),
          sessionCardId: db.sessionCardId,
        )['toCardCustomerId'],
        'La carte de destination doit être différente de la carte de départ.',
      );
      // Virgule décimale → point (montant num) ; refusée au catalogue (FCFA entiers).
      expect(parseMoney('1 500,5'), 1500.5);
      final r = request(ServiceType.transfer, {'toCardCustomerId': '121 436 999', 'amount': '1 500,5'});
      expect(r.cardBody, {'fromCardCustomerId': db.sessionCardId, 'toCardCustomerId': '121436999', 'amount': 1500.5});
      expect(
        validateForm(serviceConfig(ServiceType.cash), {
          'amount': '1000,5',
          'deliveryChannel': 'SMS',
          'beneficiaryContact': '0167123456',
        }, const FormSelection())['amount'],
        "Montant entier attendu (le franc CFA n'a pas de centimes).",
      );

      const momo = WalletChannel(slug: 'MOMO', label: 'MTN Mobile Money');
      const bmo = WalletChannel(slug: 'BMO', label: 'BestCash Money', holderVerification: true);
      final payout = serviceConfig(ServiceType.payout);
      final values = {'wallet': 'MOMO', 'phone': '0197000018', 'amount': '10000'};
      expect(validateForm(payout, values, const FormSelection(wallet: momo)).keys, ['firstName', 'lastName']);
      expect(validateForm(payout, {...values, 'wallet': 'BMO'}, const FormSelection(wallet: bmo)), isEmpty);
      final p = request(ServiceType.payout, {...values, 'wallet': 'BMO'}, const FormSelection(wallet: bmo));
      expect(p.cardBody, {
        'cardCustomerId': db.sessionCardId,
        'amount': 10000,
        'phone': '+2290197000018',
        'wallet': 'BMO',
      });

      const range = MobileProduct(id: '17', name: 'Recharge MTN', priceType: 'RANGE', minPrice: 100, maxPrice: 30000);
      final airtime = serviceConfig(ServiceType.airtime);
      expect(
        validateForm(airtime, {
          'beneficiary': '0196666262',
          'productId': '17',
          'amount': '40000',
        }, const FormSelection(product: range, productsLoaded: true))['amount'],
        'Entre ${formatFcfa(100)} et ${formatFcfa(30000)} pour cette offre.',
      );
    });
  });

  group('transfert (opération carte)', () {
    setUp(() => setUpEnv());

    PaymentRequest transfer([num amount = 15000]) =>
        request(ServiceType.transfer, {'toCardCustomerId': '121436999', 'amount': '$amount'});

    test('devis = initiation ; PIN faux puis bon → succès suivi', () async {
      expect(await flow().requestQuote(transfer()), isNull);
      final q = state().quote!;
      expect(q.isCardOperation, isTrue);
      expect(q.targetHolderName, 'Afiavi Sossou');
      expect(q.amountDebited, 15440);
      expect(state().reference, isNotNull);

      expect(await flow().submitSecret('111111'), SecretOutcome.retry);
      expect(state().pinError!.message, 'Code incorrect — 4 tentative(s) restante(s).');
      expect(state().execution, isNull);

      expect(await flow().submitSecret('482915'), SecretOutcome.submitted);
      expect(state().execution!.status, OperationStatus.success);
      final op = await flow().refreshOperation();
      expect(op!.status, OperationStatus.success);
      expect(op.counterparty, 'Afiavi Sossou · •••• 9034');
      expect(op.reference, startsWith('COP-'));
    });

    test('abandon : l’opération initiée est annulée (DELETE)', () async {
      await flow().requestQuote(transfer());
      final id = state().quote!.operationId!;
      await flow().abandon();
      expect(db.operationById(id)!['status'], 'CANCELLED');
      expect(state().quote, isNull);
    });

    test('nouveau devis : l’ancienne opération est annulée, nouveau requestId', () async {
      await flow().requestQuote(transfer());
      final first = state().quote!.operationId!;
      final ref1 = state().reference;
      expect(await flow().requote(), isTrue);
      expect(db.operationById(first)!['status'], 'CANCELLED');
      expect(state().quote!.operationId, isNot(first));
      expect(state().reference, isNot(ref1));
    });

    test('500 « NE LA RELANCEZ PAS » → en vérification, suivi de l’opération', () async {
      await flow().requestQuote(transfer(99999));
      expect(await flow().submitSecret('482915'), SecretOutcome.submitted);
      expect(state().review!.message, contains('NE LA RELANCEZ PAS'));
      expect(state().operationId, state().quote!.operationId);
      final op = await flow().refreshOperation();
      expect(op!.status, OperationStatus.failed);
    });

    test('voie OTP : code épuisé → recommencer', () async {
      container.dispose();
      await setUpEnv(hasPin: false);
      await flow().requestQuote(transfer());
      expect(state().quote!.requiresConfirmation, isTrue);
      expect(state().quote!.sentTo, '********456');
      expect(await flow().submitSecret('000000'), SecretOutcome.retry);
      expect(await flow().submitSecret('000000'), SecretOutcome.retry);
      expect(await flow().submitSecret('000000'), SecretOutcome.restart);
      expect(state().restartRequired, isTrue);
      expect(await flow().requote(), isTrue);
      expect(await flow().submitSecret('123456'), SecretOutcome.submitted);
    });

    test('erreur de devis : refus serveur renvoyé au formulaire', () async {
      final failure = await flow().requestQuote(
        request(ServiceType.transfer, {'toCardCustomerId': '999999999', 'amount': '1000'}),
      );
      expect(failure!.failure.code, ErrorCodes.notFound);
      expect(state().quote, isNull);
    });
  });

  group('catalogue', () {
    setUp(() => setUpEnv());

    PaymentRequest data() => request(
      ServiceType.data,
      {'beneficiary': '0196666262', 'productId': '18490'},
      const FormSelection(
        product: MobileProduct(id: '18490', name: '5 Go', priceType: 'FIXED', price: 3000),
        productsLoaded: true,
      ),
    );

    test('devis refusé : motif et contrôles en échec', () async {
      final failure = await flow().requestQuote(
        request(ServiceType.elec, {
          'meterNum': '01234560000',
          'amount': '5000',
          'recipientChannel': 'whatsapp',
          'recipientContact': '0167123456',
        }),
      );
      expect(failure!.failure.message, startsWith('Ce compteur n’a pas pu être vérifié.'));
      expect(failure.failedChecks.single.key, 'meter');
    });

    test('devis trop ancien : pas d’envoi du PIN, nouveau devis demandé', () async {
      await flow().requestQuote(data());
      final quoteId = state().quote!.quoteId;
      db.advance(const Duration(minutes: 9, seconds: 5));
      expect(await flow().submitSecret('111111'), SecretOutcome.requote);
      expect(db.pinAttemptsLeft, 5, reason: 'aucun essai de PIN consommé');
      expect(state().needsRequote, isTrue);
      expect(await flow().requote(), isTrue);
      expect(state().quote!.quoteId, isNot(quoteId));
      expect(state().needsRequote, isFalse);
    });

    test('confirmation : même référence pour la tentative, succès immédiat', () async {
      await flow().requestQuote(data());
      final reference = state().reference!;
      expect(await flow().submitSecret('482915'), SecretOutcome.submitted);
      expect(state().execution!.completed, isTrue);
      expect(db.operations.first['idempotencyKey'], reference);
    });

    test('plafond journalier : devis brûlé → refaire le devis', () async {
      db.dailyOperations = 15;
      await flow().requestQuote(data());
      expect(await flow().submitSecret('482915'), SecretOutcome.retry);
      expect(state().pinError!.code, ErrorCodes.dailyOperationLimit);
      expect(state().needsRequote, isTrue);
    });

    test('recharge B-MO : code refusé, puis accepté', () async {
      const bmo = WalletChannel(slug: 'BMO', label: 'BestCash Money', holderVerification: true);
      await flow().requestQuote(
        request(ServiceType.topup, {
          'wallet': 'BMO',
          'payerIdentifier': '0196000062',
          'amount': '5000',
        }, const FormSelection(wallet: bmo)),
      );
      expect(state().quote!.fundingApproval, 'CONFIRMATION_CODE');
      expect(await flow().confirmExternal(), isNull);
      expect(state().awaiting, ExecutionResult.confirmationCode);
      final bad = await flow().submitFundingCode('0000');
      expect(bad!.code, 'INVALID_CONFIRMATION_CODE');
      expect(bad.details['attemptsLeft'], 2);
      expect(await flow().submitFundingCode('482913'), isNull);
      expect(state().operation!.status, OperationStatus.success);
    });
  });
}
