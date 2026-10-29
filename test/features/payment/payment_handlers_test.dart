import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_api.dart';

import 'payment_test_utils.dart';

void main() {
  late ClockDb db;
  late FakeClient c;

  setUp(() {
    db = ClockDb();
    c = FakeClient(db);
  });

  Future<Map<String, dynamic>> initTransfer({num amount = 15000, String to = '121436999', String? requestId}) async {
    final r = await c.post('/cards/transfer/initiate', {
      'fromCardCustomerId': db.sessionCardId,
      'toCardCustomerId': to,
      'amount': amount,
      'requestId': ?requestId,
    });
    expect(r.status, 200, reason: '${r.body}');
    return r.json;
  }

  group('transfert carte → carte', () {
    test('initiation puis exécution avec le PIN', () async {
      final init = await initTransfer();
      expect(init['requiresConfirmation'], isFalse);
      expect(init['otpChannel'], isNull);
      expect(init['fee'], 440);
      expect(init['amountDebited'], 15440);
      expect(init['amountCredited'], 15000);
      expect(init['targetHolderName'], 'Afiavi Sossou');
      expect(init['targetLast4'], '9034');
      final id = init['operationId'] as String;
      expect(db.operationById(id)!['status'], 'PENDING');

      final before = db.balance;
      final notifs = db.notifications.length;
      final r = await c.post('/cards/operations/$id/execute', {'pin': '482915'});
      expect(r.status, 200);
      expect(r.json['status'], 'SUCCESS');
      expect(r.json['reference'], id);
      expect(db.balance, before - 15440);
      expect(db.issuerTransactions.first['transactionDesc'], 'Transfert sortant');
      expect(db.notifications.length, notifs + 1);
      expect(db.notifications.first['linkId'], id);
      expect(db.operationDetails[id]!['movements'], isNotEmpty);

      final op = await c.get('/cards/operations/$id');
      expect(op.json['status'], 'SUCCESS');
      expect(op.json['reference'], startsWith('COP-'));
      expect((op.json['cards'] as List).map((e) => (e as Map)['role']), ['SOURCE', 'TARGET']);
      expect(op.json['service'], {'slug': 'merchant:card:transfer', 'label': 'Transfert carte à carte'});

      final again = await c.post('/cards/operations/$id/execute', {'pin': '482915'});
      expect(again.message, 'Cette opération a déjà été effectuée.');
    });

    test('PIN faux : essais restants, opération intacte, puis verrou', () async {
      final id = (await initTransfer())['operationId'] as String;
      final r = await c.post('/cards/operations/$id/execute', {'pin': '111111'});
      expect(r.status, 403);
      expect(r.code, 'FORBIDDEN');
      expect(r.message, 'Code incorrect — 4 tentative(s) restante(s).');
      expect(db.operationById(id)!['status'], 'PENDING');

      for (var i = 0; i < 3; i++) {
        await c.post('/cards/operations/$id/execute', {'pin': '111111'});
      }
      final locked = await c.post('/cards/operations/$id/execute', {'pin': '111111'});
      expect(locked.message, startsWith('Trop de codes erronés. Votre compte est bloqué pendant 15 minutes.'));
      final stillLocked = await c.post('/cards/operations/$id/execute', {'pin': '482915'});
      expect(stillLocked.message, 'Trop de codes erronés. Réessayez dans 15 minute(s), ou réinitialisez votre code.');

      db.advance(const Duration(minutes: 16));
      final ok = await c.post('/cards/operations/$id/execute', {'pin': '482915'});
      expect(ok.json['status'], 'SUCCESS');
    });

    test('validation et refus métier', () async {
      final unknown = await c.post('/cards/transfer/initiate', {
        'fromCardCustomerId': db.sessionCardId,
        'toCardCustomerId': '999999999',
        'amount': 1000,
      });
      expect(unknown.status, 404);
      expect(unknown.message, 'Aucune carte ne correspond à l’identifiant 999999999.');

      final same = await c.post('/cards/transfer/initiate', {
        'fromCardCustomerId': db.sessionCardId,
        'toCardCustomerId': db.sessionCardId,
        'amount': 1000,
      });
      expect(same.message, 'La carte de destination doit être différente de la carte de départ.');

      final poor = await c.post('/cards/transfer/initiate', {
        'fromCardCustomerId': db.sessionCardId,
        'toCardCustomerId': '121436999',
        'amount': 200000,
      });
      expect(poor.message, 'Solde insuffisant : 152400 disponible(s), 201100 nécessaire(s) (frais compris).');

      final extra = await c.post('/cards/transfer/initiate', {
        'fromCardCustomerId': db.sessionCardId,
        'toCardCustomerId': '121436999',
        'amount': 1000,
        'note': 'x',
      });
      expect(extra.code, 'VALIDATION_FAILED');
      expect(extra.json['details'], containsPair('note', ['property note should not exist']));

      final small = await c.post('/cards/transfer/initiate', {
        'fromCardCustomerId': db.sessionCardId,
        'toCardCustomerId': '121436999',
        'amount': 50,
      });
      expect(small.code, 'VALIDATION_FAILED');

      db.cardStatus = 'Inactive';
      final suspended = await c.post('/cards/transfer/initiate', {
        'fromCardCustomerId': db.sessionCardId,
        'toCardCustomerId': '121436999',
        'amount': 1000,
      });
      expect(suspended.message, startsWith('Cette carte est suspendue.'));
    });

    test('rejeu du même requestId : même opération, isReplay', () async {
      final a = await initTransfer(requestId: 'f1c9a1e2-0000-4000-8000-000000000001');
      final b = await initTransfer(requestId: 'f1c9a1e2-0000-4000-8000-000000000001');
      expect(b['operationId'], a['operationId']);
      expect(b['isReplay'], isTrue);
    });

    test('voie OTP (porteur sans PIN) : 3 essais, code 000000 refusé', () async {
      db.pin = null;
      final init = await initTransfer();
      expect(init['requiresConfirmation'], isTrue);
      expect(init['otpChannel'], 'SMS');
      expect(init['sentTo'], '********456');
      expect(init['expiresInSeconds'], 300);
      expect(init['attemptsLeft'], 3);
      final id = init['operationId'] as String;
      expect(db.operationById(id)!['status'], 'PENDING_APPROVAL');

      final viaPin = await c.post('/cards/operations/$id/execute', {'pin': '482915'});
      expect(viaPin.message, 'Cette opération n’est pas confirmable (état PENDING_APPROVAL).');

      final wrong = await c.post('/cards/operations/confirm', {'operationId': id, 'code': '000000'});
      expect(wrong.message, 'Code incorrect — 2 tentative(s) restante(s).');
      final ok = await c.post('/cards/operations/confirm', {'operationId': id, 'code': '123456'});
      expect(ok.json['status'], 'SUCCESS');

      final id2 = (await initTransfer())['operationId'] as String;
      await c.post('/cards/operations/confirm', {'operationId': id2, 'code': '000000'});
      await c.post('/cards/operations/confirm', {'operationId': id2, 'code': '000000'});
      final third = await c.post('/cards/operations/confirm', {'operationId': id2, 'code': '000000'});
      expect(third.message, 'Code incorrect. L’opération a été annulée par sécurité.');
      expect(db.operationById(id2)!['status'], 'CANCELLED');

      final id3 = (await initTransfer())['operationId'] as String;
      db.advance(const Duration(minutes: 6));
      final late = await c.post('/cards/operations/confirm', {'operationId': id3, 'code': '123456'});
      expect(late.message, 'Le code a expiré. Recommencez l’opération pour en recevoir un nouveau.');
    });

    test('annulation (DELETE) avant exécution', () async {
      final id = (await initTransfer())['operationId'] as String;
      final r = await c.call('DELETE', '/cards/operations/$id', body: {'reason': "Abandon par l'utilisateur"});
      expect(r.json, {'success': true, 'operationId': id, 'message': 'Opération annulée.'});
      expect(db.operationById(id)!['status'], 'CANCELLED');
      final again = await c.call('DELETE', '/cards/operations/$id');
      expect(
        again.message,
        'Cette opération ne peut plus être annulée : elle est déjà en cours de traitement ou terminée.',
      );
      final exec = await c.post('/cards/operations/$id/execute', {'pin': '482915'});
      expect(exec.message, 'Cette opération a été annulée.');
      final status = await c.get('/cards/operations/$id');
      expect(status.json['reason'], "Abandon par l'utilisateur");
    });

    test('sort indéterminé : 500 « NE LA RELANCEZ PAS », opération FAILED', () async {
      final id = (await initTransfer(amount: 99999))['operationId'] as String;
      final r = await c.post('/cards/operations/$id/execute', {'pin': '482915'});
      expect(r.status, 500);
      expect(r.message, contains('NE LA RELANCEZ PAS'));
      expect((await c.get('/cards/operations/$id')).json['status'], 'FAILED');
    });
  });

  group('retrait vers Mobile Money (voie cards)', () {
    Future<FakeResponse> payout(Map<String, dynamic> extra) => c.post('/cards/to-mobile-money/initiate', {
      'cardCustomerId': db.sessionCardId,
      'amount': 10000,
      'phone': '+2290197000018',
      ...extra,
    });

    test('nom et prénom requis hors B-MO', () async {
      final r = await payout({'wallet': 'MOMO'});
      expect(r.message, 'Le prénom et le nom du bénéficiaire sont requis pour ce portefeuille.');
      final ok = await payout({'wallet': 'MOMO', 'firstName': 'Afi', 'lastName': 'Mensah'});
      expect(ok.json['fee'], 220);
      expect(ok.json['amountDebited'], 10220);
      expect(ok.json.containsKey('targetLast4'), isFalse);
    });

    test('B-MO : titulaire vérifié, numéro sans compte refusé', () async {
      final ok = await payout({'wallet': 'bmo'});
      final id = ok.json['operationId'] as String;
      final parties = (await c.get('/cards/operations/$id')).json['parties'] as List;
      expect(parties.single, containsPair('verified', true));
      expect(parties.single, containsPair('name', 'Afi Mensah'));
      final none = await payout({'wallet': 'BMO', 'phone': '+2290197000000'});
      expect(none.message, startsWith('Ce numéro n’a pas de compte BestCash Money'));
      final exec = await c.post('/cards/operations/$id/execute', {'pin': '482915'});
      expect(exec.json['details'], contains('providerReference'));
      expect(db.issuerTransactions.first['transactionDesc'], 'Retrait vers BestCash Money');
    });

    test('catalogue des portefeuilles', () async {
      final r = await c.get('/external-wallets/channels', {'country': 'BJ', 'operation': 'PAYOUT'});
      final data = (r.json['data'] as List).cast<Map<String, dynamic>>();
      expect(data.map((d) => d['providerSlug']), ['MOMO', 'MOOVMONEY', 'CELTISCASH', 'BMO']);
      expect(data.last['holderVerification'], isTrue);
      expect(data.last['collectApproval'], 'CONFIRMATION_CODE');
      expect(r.json['count'], 4);
    });
  });

  group('catalogue', () {
    Map<String, dynamic> card() => {
      'source': 'CUSTOMER_CARD',
      'card': {'cardCustomerId': db.sessionCardId},
    };

    Future<Map<String, dynamic>> quote(
      String service,
      Map<String, dynamic> input, {
      Map<String, dynamic>? funding,
    }) async {
      final r = await c.post('/catalog/quote', {'service': service, 'funding': funding ?? card(), 'input': input});
      expect(r.status, 200, reason: '${r.body}');
      return r.json;
    }

    Future<FakeResponse> confirm(Map<String, dynamic> q, String service, {String? reference, String? pin = '482915'}) =>
        c.post('/catalog/confirm', {
          'quoteId': q['quoteId'],
          'service': service,
          'funding': card(),
          'reference': ?reference,
          'pin': ?pin,
        });

    test('lookups opérateur, électricité et TV', () async {
      final topup = await c.get('/catalog/lookup/mobile/0196666262/products', {'type': 'TOPUP'});
      final products = (topup.json['data'] as List).cast<Map<String, dynamic>>();
      expect(products.first, containsPair('priceType', 'RANGE'));
      expect(products.first['name'], 'Recharge MTN');
      final data = await c.get('/catalog/lookup/mobile/+2290196666262/products', {'type': 'data'});
      expect((data.json['data'] as List).length, 4);
      final bad = await c.get('/catalog/lookup/mobile/12/products');
      expect(bad.message, startsWith('Numéro invalide.'));
      final type = await c.get('/catalog/lookup/mobile/0196666262/products', {'type': 'X'});
      expect(type.message, 'type : TOPUP, DATA, COMBO ou MOBILE_PIN.');
      final unknown = await c.get('/catalog/lookup/mobile/0196660000/products');
      expect(unknown.status, 500);
      final invoices = await c.get('/catalog/lookup/electricity/610201551642KA/invoices');
      expect((invoices.json['data'] as Map)['invoices'], hasLength(3));
      final tv = await c.get('/catalog/lookup/tv/24100027499297/current');
      expect((tv.json['data'] as Map)['mainOfferLabel'], 'ACCESS');
      final offers = await c.get('/catalog/lookup/tv/24100027499297/offers');
      expect(((offers.json['data'] as Map)['offersList'] as List).length, 3);
    });

    test('devis établi (forfait) puis relecture', () async {
      final q = await quote('mobile-data', {'beneficiary': '0196666262', 'productId': '18490'});
      expect(q['feasible'], isTrue);
      expect(q['amount'], 3000);
      expect(q['amountDebited'], 3000);
      expect((q['display'] as Map)['productName'], '5 Go - 30 jours');
      expect((q['display'] as Map)['beneficiary'], '+2290196666262');
      expect(DateTime.parse(q['expiresAt'] as String).difference(db.now()).inMinutes, 10);
      final peek = await c.get('/catalog/quote/${q['quoteId']}');
      expect(peek.json['status'], 'OPEN');
      expect(peek.json['feasible'], isTrue);
      expect(peek.json['isExpired'], isFalse);
      expect((await c.get('/catalog/quote/nope')).message, 'Devis introuvable.');
    });

    test('devis refusé (200, feasible:false) et refus HTTP', () async {
      final q = await quote('electricity-prepaid', {
        'meterNum': '01234560000',
        'recipientChannel': 'whatsapp',
        'recipientContact': '+2290167123456',
        'amount': 5000,
      });
      expect(q['feasible'], isFalse);
      expect(q['reason'], startsWith('Ce compteur n’a pas pu être vérifié.'));
      expect(q['amountDebited'], 0);
      expect((q['checks'] as List).last, containsPair('key', 'meter'));

      final contract = await c.post('/catalog/quote', {
        'service': 'electricity-prepaid',
        'funding': card(),
        'input': {'meterNum': 'abc', 'recipientChannel': 'sms', 'recipientContact': 'x', 'amount': 5000},
      });
      expect(contract.code, 'REQUEST_REJECTED');
      expect(
        contract.message,
        startsWith('Données invalides pour le service « electricity-prepaid » — input.meterNum'),
      );

      final purchase = await c.post('/catalog/quote', {'service': 'card-purchase', 'funding': card(), 'input': {}});
      expect(purchase.code, 'SERVICE_NOT_SELF_SERVICE');
      final merchant = await c.post('/catalog/quote', {
        'service': 'mobile-topup',
        'funding': {'source': 'MERCHANT_WALLET'},
        'input': {'beneficiary': '0196666262', 'productId': '17', 'amount': 500},
      });
      expect(merchant.code, 'FUNDS_SOURCE_NOT_ALLOWED');
      final w2cByCard = await c.post('/catalog/quote', {
        'service': 'wallet-to-card',
        'funding': card(),
        'input': {'cardCustomerId': db.sessionCardId, 'amount': 5000},
      });
      expect(w2cByCard.status, 404);

      final range = await quote('mobile-topup', {'beneficiary': '0196666262', 'productId': '17', 'amount': 50000});
      expect(range['reason'], 'Montant hors bornes pour ce produit : entre 100 et 30000 XOF.');
    });

    test('confirmation : PIN vérifié d’abord, idempotence par référence', () async {
      final q = await quote('mobile-topup', {'beneficiary': '0196666262', 'productId': '17', 'amount': 1000});
      final wrong = await confirm(q, 'mobile-topup', reference: 'ref-1', pin: '111111');
      expect(wrong.status, 403);
      expect(wrong.message, 'Code incorrect — 4 tentative(s) restante(s).');
      expect(db.quotes[q['quoteId']]!['status'], 'OPEN');

      final noPin = await confirm(q, 'mobile-topup', reference: 'ref-1', pin: null);
      expect(noPin.code, 'CARD_CONSENT_REQUIRED');

      final before = db.balance;
      final ok = await confirm(q, 'mobile-topup', reference: 'ref-1');
      expect(ok.json['completed'], isTrue);
      expect(ok.json['status'], 'SUCCESS');
      expect(ok.json['merchantReference'], 'ref-1');
      expect(ok.json['reference'], startsWith('ADS-'));
      expect(db.balance, before - 1000);
      expect(db.operations.first['id'], ok.json['operationId']);
      expect(db.operationDetails[ok.json['operationId']]!['quote'], isNotNull);
      expect(db.notifications.first['kind'], 'FINANCIAL');

      final replay = await confirm(q, 'mobile-topup', reference: 'ref-1');
      expect(replay.json['operationId'], ok.json['operationId']);
      expect(replay.json['message'], startsWith('Opération déjà effectuée'));
      expect(db.balance, before - 1000);

      final reused = await confirm(q, 'mobile-topup', reference: 'ref-2');
      expect(reused.message, 'Ce devis a déjà servi. Demandez-en un nouveau.');
    });

    test('devis expiré, débit refusé, service non rendu', () async {
      final q = await quote('cash-withdrawal', {
        'deliveryChannel': 'SMS',
        'beneficiaryContact': '+2290167123456',
        'pin': '4829',
        'amount': 10000,
      });
      expect((q['display'] as Map)['pinIsProvided'], isTrue);
      expect(q['internalFee'], 100);
      expect(q['warnings'], contains(startsWith('Le code d’accès n’est pas transmis')));
      db.advance(const Duration(minutes: 11));
      final expired = await confirm(q, 'cash-withdrawal', reference: 'r-exp');
      expect(expired.message, 'Ce devis a expiré. Les prix ont pu changer : demandez-en un nouveau.');

      db.balance = 500;
      final q2 = await quote('cash-withdrawal', {
        'deliveryChannel': 'SMS',
        'beneficiaryContact': '+2290167123456',
        'amount': 10000,
      });
      final refused = await confirm(q2, 'cash-withdrawal', reference: 'r-poor');
      expect(refused.message, 'Débit de la carte refusé : Solde insuffisant.');
      expect(db.operations.first['status'], 'FAILED');

      db.balance = 100000;
      final q3 = await quote('electricity-prepaid', {
        'meterNum': '01234569999',
        'recipientChannel': 'email',
        'recipientContact': 'awa@example.com',
        'amount': 5000,
      });
      final notRendered = await confirm(q3, 'electricity-prepaid', reference: 'r-elec');
      expect(notRendered.status, 500);
      expect(notRendered.message, contains('Vous avez été remboursé'));
      expect(db.operations.first['status'], 'REFUNDED');
      expect(db.balance, 100000);
    });

    test('plafonds journaliers et plafond de devis', () async {
      db.dailyAmount = 499500;
      final q = await quote('mobile-topup', {'beneficiary': '0196666262', 'productId': '17', 'amount': 1000});
      final amount = await confirm(q, 'mobile-topup', reference: 'r-a');
      expect(amount.status, 403);
      expect(amount.code, 'DAILY_AMOUNT_LIMIT');
      expect(db.quotes[q['quoteId']]!['status'], 'CONSUMED');

      db
        ..dailyAmount = 0
        ..dailyOperations = 15;
      final q2 = await quote('mobile-topup', {'beneficiary': '0196666262', 'productId': '17', 'amount': 1000});
      expect((await confirm(q2, 'mobile-topup', reference: 'r-b')).code, 'DAILY_OPERATION_LIMIT');

      for (var i = 0; i < 58; i++) {
        await quote('mobile-topup', {'beneficiary': '0196666262', 'productId': '21'});
      }
      final limited = await c.post('/catalog/quote', {
        'service': 'mobile-topup',
        'funding': card(),
        'input': {'beneficiary': '0196666262', 'productId': '21'},
      });
      expect(limited.code, 'QUOTE_RATE_LIMIT');
    });

    Map<String, dynamic> wallet(String slug, String phone, {bool names = true}) => {
      'source': 'CUSTOMER_EXTERNAL_CHANNEL',
      'external': {
        'channelSlug': slug,
        'payerIdentifier': phone,
        if (names) ...{'payerFirstName': 'Awa', 'payerLastName': 'Houngbédji'},
        'countryCode': 'BJ',
      },
    };

    test('recharge depuis MTN MoMo : validation sur téléphone, puis carte créditée avec le temps', () async {
      final noName = await quote('wallet-to-card', {
        'cardCustomerId': db.sessionCardId,
        'amount': 20000,
      }, funding: wallet('MOMO', '+2290196000062', names: false));
      expect(
        noName['reason'],
        'Le prénom et le nom du payeur sont requis pour MTN Mobile Money : l’opérateur les exige.',
      );

      final f = wallet('MOMO', '+2290196000062');
      final q = await quote('wallet-to-card', {'cardCustomerId': db.sessionCardId, 'amount': 20000}, funding: f);
      expect(q['internalFee'], 200);
      expect(q['externalFeeAdvanced'], 300);
      expect(q['amountDebited'], 20500);
      expect((q['display'] as Map)['fundingApproval'], 'PAYER_APPROVAL');
      expect((q['display'] as Map)['cardWillReceive'], 20000);

      final r = await c.post('/catalog/confirm', {
        'quoteId': q['quoteId'],
        'service': 'wallet-to-card',
        'funding': f,
        'reference': 'w2c-1',
      });
      expect(r.json['completed'], isFalse);
      expect(r.json['awaiting'], 'PAYER_APPROVAL');
      final id = r.json['operationId'] as String;

      final before = db.balance;
      final pending = await c.get('/cards/operations/$id');
      expect(pending.json['status'], 'PENDING');
      expect(pending.json['awaiting'], 'PAYER_APPROVAL');
      expect(db.balance, before);

      final noCode = await c.post('/commerce/operations/$id/funding/confirm', {'code': '1234'});
      expect(noCode.code, 'NOT_A_CODE_PAYMENT');
      final del = await c.call('DELETE', '/cards/operations/$id');
      expect(del.code, 'USE_FUNDING_CANCEL');

      db.advance(const Duration(seconds: 16));
      final done = await c.get('/cards/operations/$id');
      expect(done.json['status'], 'SUCCESS');
      expect(done.json['awaiting'], isNull);
      expect(db.balance, before + 20000);
      expect(db.issuerTransactions.first['transactionDesc'], 'Rechargement depuis MTN Mobile Money');
    });

    test('recharge depuis B-MO : code de confirmation (3 essais) ou annulation', () async {
      final f = wallet('BMO', '+2290196000062', names: false);
      final q = await quote('wallet-to-card', {'cardCustomerId': db.sessionCardId, 'amount': 5000}, funding: f);
      expect(q['externalFeeAdvanced'], 0);
      expect((q['display'] as Map)['fundingApproval'], 'CONFIRMATION_CODE');
      expect((q['display'] as Map)['payerVerifiedName'], 'Kossi A.');
      final r = await c.post('/catalog/confirm', {
        'quoteId': q['quoteId'],
        'service': 'wallet-to-card',
        'funding': f,
        'reference': 'bmo-1',
      });
      expect(r.json['awaiting'], 'CONFIRMATION_CODE');
      final id = r.json['operationId'] as String;

      final bad = await c.post('/commerce/operations/$id/funding/confirm', {'code': '0000'});
      expect(bad.code, 'INVALID_CONFIRMATION_CODE');
      expect(bad.message, 'Code refusé. 2 essai(s) restant(s).');
      expect(bad.json['details'], {'attemptsLeft': 2});
      final format = await c.post('/commerce/operations/$id/funding/confirm', {'code': '12'});
      expect(format.code, 'VALIDATION_FAILED');

      final before = db.balance;
      final ok = await c.post('/commerce/operations/$id/funding/confirm', {'code': '482913'});
      expect(ok.json['completed'], isTrue);
      expect(ok.json['status'], 'SUCCESS');
      expect(db.balance, before + 5000);

      final q2 = await quote('wallet-to-card', {'cardCustomerId': db.sessionCardId, 'amount': 5000}, funding: f);
      final r2 = await c.post('/catalog/confirm', {
        'quoteId': q2['quoteId'],
        'service': 'wallet-to-card',
        'funding': f,
        'reference': 'bmo-2',
      });
      final id2 = r2.json['operationId'] as String;
      final cancel = await c.post('/commerce/operations/$id2/funding/cancel');
      expect(cancel.json['status'], 'CANCELLED');
      expect(cancel.json['completed'], isFalse);
      final after = await c.post('/commerce/operations/$id2/funding/confirm', {'code': '482913'});
      expect(after.code, 'OPERATION_NOT_PENDING');

      final none = await quote('wallet-to-card', {
        'cardCustomerId': db.sessionCardId,
        'amount': 5000,
      }, funding: wallet('BMO', '+2290196000000', names: false));
      expect(none['reason'], startsWith('Ce numéro n’a pas de compte BestCash Money'));
    });
  });
}
