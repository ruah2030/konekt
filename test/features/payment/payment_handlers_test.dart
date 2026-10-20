import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/operation.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/features/payment/data/payment_repository.dart';

import '../../helpers/test_app.dart';
import 'payment_test_utils.dart';

void main() {
  late ClockDb db;
  late ProviderContainer container;
  late PaymentRepository repo;

  setUp(() async {
    db = ClockDb();
    final env = await TestEnv.create(signedIn: true, db: db);
    container = env.container();
    repo = container.read(paymentRepositoryProvider);
  });

  tearDown(() => container.dispose());

  Future<ApiFailure> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } catch (e) {
      return ApiFailure.from(e);
    }
    fail('Une erreur était attendue');
  }

  group('POST /v1/quotes', () {
    test('frais calculés par le serveur (grille de la maquette)', () async {
      final transfer = await repo.requestQuote({'service': 'transfer', 'target': '987654321', 'amount': 20000});
      expect((transfer.fee, transfer.total), (440, 20440));
      expect(transfer.beneficiary, 'Afiavi Sossou · •••• 4321');
      expect(transfer.checks.single.label, 'Bénéficiaire');
      expect(transfer.expiresAt.difference(db.clock).inMinutes, 10);
      expect(db.quotes.containsKey(transfer.quoteId), isTrue);

      final payout = await repo.requestQuote({
        'service': 'payout',
        'operator': 'moov',
        'msisdn': '+229 01 97 00 00 18',
        'amount': 10000,
      });
      expect(payout.fee, 220);
      expect(payout.beneficiary, 'Moov Money · +229 01 97 00 00 18');
      expect(payout.warnings, hasLength(1));

      final elec = await repo.requestQuote({
        'service': 'elec',
        'meter': '12345678901',
        'amount': 5000,
        'deliveryChannel': 'WHATSAPP',
        'contact': '+22901960000',
      });
      expect(elec.fee, 125);
      expect(elec.checks.single.detail, 'HOUNGBÉDJI AWA · ≈ 48,1 kWh');

      final data = await repo.requestQuote({'service': 'data', 'planId': 'd3', 'msisdn': '+22901960000'});
      expect((data.amount, data.fee, data.total), (6000, 0, 6000));

      final cash = await repo.requestQuote({'service': 'cash', 'amount': 10000});
      expect(cash.fee, 100);

      final topup = await repo.requestQuote({
        'service': 'topup',
        'operator': 'mtn',
        'msisdn': '+22901960000',
        'amount': 300000,
      });
      expect((topup.fee, topup.requiresUserApproval, topup.operatorLabel), (3000, true, 'MTN MoMo'));
    });

    test('solde insuffisant (frais compris)', () async {
      final f = await failure(
        () => repo.requestQuote({'service': 'transfer', 'target': '987654321', 'amount': 200000}),
      );
      expect(f.code, ErrorCodes.insufficientFunds);
      expect(f.message, 'Solde insuffisant : il manque ${formatFcfa(49000)} (frais compris).');
    });

    test('plafond de 500 000 FCFA sur 24 h', () async {
      db.dailySpent = 450000;
      final f = await failure(() => repo.requestQuote({'service': 'cash', 'amount': 60000}));
      expect(f.code, ErrorCodes.dailyAmountLimit);
      expect(f.message, 'Ce montant dépasse votre plafond de 500 000 FCFA sur 24 heures.');
    });

    test('carte bénéficiaire identique à la sienne', () async {
      final f = await failure(
        () => repo.requestQuote({'service': 'transfer', 'target': db.sessionCardId, 'amount': 1000}),
      );
      expect(f.code, ErrorCodes.requestRejected);
      expect(f.message, 'La carte bénéficiaire doit être différente de la vôtre.');
    });

    test('carte non active → 403', () async {
      db.cardStatus = 'INACTIVE';
      final f = await failure(() => repo.requestQuote({'service': 'cash', 'amount': 1000}));
      expect((f.code, f.statusCode), (ErrorCodes.forbidden, 403));
      expect(f.message, 'Cette carte est suspendue. Réactivez-la pour payer à nouveau.');
    });

    test('forfaits internet', () async {
      final plans = await repo.dataPlans();
      expect(plans.map((p) => p.price), [1000, 3000, 6000, 12000]);
      expect(plans.first.label, '1,5 Go');
    });
  });

  group('POST /v1/operations', () {
    Future<String> quote() async =>
        (await repo.requestQuote({'service': 'transfer', 'target': '987654321', 'amount': 10000})).quoteId;

    test('PIN faux puis verrouillage après 5 essais', () async {
      final id = await quote();
      var f = await failure(() => repo.execute(quoteId: id, pin: '000000'));
      expect(f.code, ErrorCodes.forbidden);
      expect(f.message, 'Code secret incorrect. 4 essai(s) avant verrouillage.');
      expect(f.details['triesLeft'], 4);
      for (var i = 0; i < 3; i++) {
        await failure(() => repo.execute(quoteId: id, pin: '000000'));
      }
      f = await failure(() => repo.execute(quoteId: id, pin: '000000'));
      expect(f.message, 'Trop de codes erronés. Réessayez dans 15 minutes, ou réinitialisez votre code secret.');
      expect(f.details['lockedUntil'], isNotNull);

      f = await failure(() => repo.execute(quoteId: id, pin: '482915'));
      expect(f.message, 'Réessayez dans 15 minute(s), ou réinitialisez votre code secret.');

      db.advance(const Duration(minutes: 9));
      final fresh = await quote();
      f = await failure(() => repo.execute(quoteId: fresh, pin: '482915'));
      expect(f.message, 'Réessayez dans 6 minute(s), ou réinitialisez votre code secret.');

      db.advance(const Duration(minutes: 6));
      final op = await repo.execute(quoteId: fresh, pin: '482915');
      expect(op.status, OperationStatus.processing);
      expect(db.pinTries, 5);
    });

    test('devis expiré', () async {
      final id = await quote();
      db.advance(const Duration(minutes: 11));
      final f = await failure(() => repo.execute(quoteId: id, pin: '482915'));
      expect(f.code, ErrorCodes.requestRejected);
      expect(f.message, 'Prix expiré. Refaites le devis.');
    });

    test('idempotence : même clé → même opération', () async {
      final id = await quote();
      final before = db.operations.length;
      final a = await repo.execute(quoteId: id, pin: '482915');
      final b = await repo.execute(quoteId: id, pin: '482915');
      expect(b.id, a.id);
      expect(db.operations.length, before + 1);
      expect(db.idempotency[id], a.id);
    });

    test('progression jusqu’à SUCCESS et mise à jour du solde', () async {
      final id = await quote();
      final op = await repo.execute(quoteId: id, pin: '482915');
      expect((op.status, op.step), (OperationStatus.processing, OperationStep.authorized));

      db.advance(const Duration(milliseconds: 1200));
      expect((await repo.track(op.id)).step, OperationStep.processing);
      expect(db.balance, 152400);

      db.advance(const Duration(seconds: 2));
      final done = await repo.track(op.id);
      expect(done.status, OperationStatus.success);
      expect(db.balance, 152400 - 10150);
      expect(db.dailySpent, 10150);
      expect(db.transactions.first['kind'], 'transfer');
      expect(db.transactions.first['amount'], -10150);
      expect(db.notifications.first['title'], 'Envoyer vers une carte · réussi');
      // La lecture standard renvoie aussi l'état final.
      expect((await container.read(paymentRepositoryProvider).track(op.id)).isFinal, isTrue);
    });

    test('recharge : attente de validation puis carte créditée', () async {
      final q = await repo.requestQuote({
        'service': 'topup',
        'operator': 'mtn',
        'msisdn': '+22901960000',
        'amount': 20000,
      });
      final op = await repo.execute(quoteId: q.quoteId, pin: '482915');
      db.advance(const Duration(seconds: 2));
      expect((await repo.track(op.id)).step, OperationStep.awaitingUserApproval);
      db.advance(const Duration(seconds: 4));
      final done = await repo.track(op.id);
      expect(done.status, OperationStatus.success);
      expect(done.isCredit, isTrue);
      expect(db.balance, 152400 + 20000);
    });

    test('électricité : code de recharge dans le reçu', () async {
      final q = await repo.requestQuote({
        'service': 'elec',
        'meter': '12345678901',
        'amount': 5000,
        'deliveryChannel': 'EMAIL',
        'contact': 'a@b.bj',
      });
      final op = await repo.execute(quoteId: q.quoteId, pin: '482915');
      db.advance(const Duration(seconds: 3));
      final done = await repo.track(op.id);
      expect(done.extra.single.value, '4821 0937 5520 1184 6653');
      expect(done.extra.single.note, 'Aussi envoyé par E-mail');
    });
  });
}
