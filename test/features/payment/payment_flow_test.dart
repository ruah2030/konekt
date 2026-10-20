import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/operation.dart';
import 'package:konekt/core/domain/service_type.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/features/account/presentation/account_providers.dart';
import 'package:konekt/features/payment/presentation/providers/payment_flow.dart';

import '../../helpers/test_app.dart';
import 'payment_test_utils.dart';

void main() {
  late ClockDb db;
  late ProviderContainer container;
  PaymentFlowController flow() => container.read(paymentFlowProvider.notifier);
  PaymentFlowState state() => container.read(paymentFlowProvider);

  setUp(() async {
    db = ClockDb();
    final env = await TestEnv.create(signedIn: true, db: db);
    container = env.container();
    container.listen(paymentFlowProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  test('validations locales (messages de la maquette)', () async {
    Future<String?> msg(ServiceType s, Map<String, String> form, [String? opt]) async =>
        (await flow().requestQuote(s, form, opt))?.message;

    expect(await msg(ServiceType.payout, {}), 'Choisissez : opérateur.');
    expect(await msg(ServiceType.topup, {}), 'Choisissez : payer avec.');
    expect(
      await msg(ServiceType.payout, {'msisdn': ' ', 'amount': '100'}, 'mtn'),
      'Numéro du portefeuille : champ obligatoire.',
    );
    expect(await msg(ServiceType.airtime, {'msisdn': '12ab', 'amount': '500'}), 'Numéro de téléphone invalide.');
    expect(await msg(ServiceType.cash, {'amount': '50'}), 'Montant minimum : 100 FCFA.');
    expect(await msg(ServiceType.cash, {'amount': '1 000 001'}), 'Montant maximum : 1 000 000 FCFA.');
    expect(
      await msg(ServiceType.elec, {'meter': '12a', 'amount': '1000', 'contact': 'x'}, 'EMAIL'),
      'Numéro de compteur : chiffres uniquement.',
    );
    final invalid = await flow().requestQuote(ServiceType.cash, {'amount': '50'}, null);
    expect(invalid!.code, ErrorCodes.validationFailed);
    expect(state().quote, isNull);
  });

  test('carte bénéficiaire = sa carte (vérifiée localement une fois la carte chargée)', () async {
    await container.read(cardProvider.future);
    final f = await flow().requestQuote(ServiceType.transfer, {'target': '121 436 474', 'amount': '1000'}, null);
    expect(f!.code, ErrorCodes.requestRejected);
    expect(f.message, 'La carte bénéficiaire doit être différente de la vôtre.');
  });

  test('devis, PIN, suivi jusqu’au succès', () async {
    expect(await flow().requestQuote(ServiceType.data, {'msisdn': '+229 01 96 00 00 00'}, 'd2'), isNull);
    expect(state().quote!.total, 3000);
    expect(state().service, ServiceType.data);

    expect(await flow().submitPin('111111'), isFalse);
    expect(state().pinError!.message, 'Code secret incorrect. 4 essai(s) avant verrouillage.');

    expect(await flow().submitPin('482915'), isTrue);
    expect(state().pinError, isNull);
    expect(state().operation!.status, OperationStatus.processing);

    db.advance(const Duration(seconds: 3));
    final op = await flow().refreshOperation();
    expect(op!.status, OperationStatus.success);
    expect(state().operation!.isFinal, isTrue);
  });

  test('verrouillage : pinLockedUntil renseigné', () async {
    await flow().requestQuote(ServiceType.cash, {'amount': '1000'}, null);
    db.pinTries = 1;
    expect(await flow().submitPin('111111'), isFalse);
    expect(state().isPinLocked(DateTime.now()), isTrue);
  });

  test('devis expiré → refaire le devis avec le même formulaire', () async {
    db.advance(const Duration(minutes: -11));
    await flow().requestQuote(ServiceType.cash, {'amount': '2000'}, null);
    final first = state().quote!;
    expect(first.isExpired(DateTime.now()), isTrue);
    db.clock = DateTime.now();
    expect(await flow().requote(), isTrue);
    expect(state().quote!.quoteId, isNot(first.quoteId));
    expect(state().quote!.amount, 2000);
    expect(state().quote!.isExpired(DateTime.now()), isFalse);
  });
}
