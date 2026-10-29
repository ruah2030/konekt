import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/domain/operation.dart';
import 'package:konekt/core/domain/service_type.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/features/payment/domain/service_config.dart';
import 'package:konekt/features/payment/presentation/providers/payment_flow.dart';

import '../../helpers/test_app.dart';
import 'payment_test_utils.dart';

/// Abonnement TV (`tv-subscription`) et facture d'électricité (`electricity-postpaid`) : prix imposés.
void main() {
  group('faux backend', () {
    late ClockDb db;
    late FakeClient c;

    setUp(() {
      db = ClockDb();
      c = FakeClient(db);
    });

    Map<String, dynamic> card() => {
      'source': 'CUSTOMER_CARD',
      'card': {'cardCustomerId': db.sessionCardId},
    };

    Future<Map<String, dynamic>> quote(String service, Map<String, dynamic> input, {Object? amount}) async {
      final r = await c.post('/catalog/quote', {
        'service': service,
        'funding': card(),
        'input': input,
        'amount': ?amount,
      });
      expect(r.status, 200, reason: '${r.body}');
      return r.json;
    }

    Future<Map<String, dynamic>> confirm(Map<String, dynamic> q, String service, String reference) async {
      final r = await c.post('/catalog/confirm', {
        'quoteId': q['quoteId'],
        'service': service,
        'funding': card(),
        'reference': reference,
        'pin': '482915',
      });
      expect(r.status, 200, reason: '${r.body}');
      return r.json;
    }

    test('ServiceType : clé catalogue et slugs distinguent prépayé et postpayé', () {
      expect(ServiceType.fromApi('electricity-postpaid'), ServiceType.elecBill);
      expect(ServiceType.fromApi('merchant:addon:sell-electricity-postpaid:from-card'), ServiceType.elecBill);
      expect(ServiceType.fromApi('merchant:addon:sell-electricity-prepaid:from-bcp'), ServiceType.elec);
      expect(ServiceType.fromApi('merchant:addon:sell-tv-subscription:from-card'), ServiceType.tv);
      expect(ServiceType.tryParse('elecBill'), ServiceType.elecBill);
    });

    test('catalogue : TV disponible, facture d’électricité proposée à prix imposé', () async {
      final r = await c.get('/catalog/services');
      final data = (r.json['data'] as List).cast<Map<String, dynamic>>();
      final tv = data.firstWhere((s) => s['key'] == 'tv-subscription');
      final bill = data.firstWhere((s) => s['key'] == 'electricity-postpaid');
      expect(tv['available'], isTrue);
      expect(bill['available'], isTrue);
      expect(bill['amountMode'], 'IMPOSED');
    });

    test('lookups TV : abonnement en cours, bouquets ; carte inconnue → 500', () async {
      final current = await c.get('/catalog/lookup/tv/24100027499297/current');
      expect(current.json['data'], {
        'numCard': '24100027499297',
        'amount': 5000,
        'currency': 'XOF',
        'mainOfferLabel': 'ACCESS',
      });
      final evasion = await c.get('/catalog/lookup/tv/24100027491111/current');
      expect((evasion.json['data'] as Map)['mainOfferLabel'], 'EVASION');
      final offers = await c.get('/catalog/lookup/tv/24100027499297/offers');
      final list = ((offers.json['data'] as Map)['offersList'] as List).cast<Map<String, dynamic>>();
      expect(list.map((o) => o['code']), ['ACCESS', 'EVASION', 'TOUT_CANAL']);
      expect((list.first['durationsList'] as List).map((d) => (d as Map)['code']), ['1', '3', '6']);
      final unknown = await c.get('/catalog/lookup/tv/24100027490000/current');
      expect(unknown.status, 500);
      expect(unknown.code, 'INTERNAL_ERROR');
      expect((await c.get('/catalog/lookup/tv/ABC/offers')).status, 500);
    });

    test('lookup SBEE : factures impayées ; abonné inconnu → 500 ; aucune impayée', () async {
      final r = await c.get('/catalog/lookup/electricity/610201551642KA/invoices');
      final data = r.json['data'] as Map;
      expect(data['referenceAbonne'], '610201551642KA');
      expect(data['name'], 'KOSSI ADJOVI');
      expect((data['invoices'] as List).map((i) => (i as Map)['reference']), [
        'FAC-2026-08-014',
        'FAC-2026-09-001',
        'FAC-2026-10-007',
      ]);
      expect((await c.get('/catalog/lookup/electricity/61020150000/invoices')).status, 500);
      final none = await c.get('/catalog/lookup/electricity/61020151111/invoices');
      expect((none.json['data'] as Map)['invoices'], isEmpty);
    });

    test('TV : reconduction (sans mainOffer), montant fourni ignoré, paiement par carte', () async {
      final q = await quote('tv-subscription', {'numCard': '24100027499297', 'amount': 1});
      expect(q['feasible'], isTrue);
      expect(q['amount'], 5000);
      expect(q['internalFee'], 100);
      expect(q['amountDebited'], 5100);
      expect(q['warnings'], [
        'Montant ignoré : le prix de ce service est fixé par le fournisseur et appliqué d’office.',
      ]);
      expect(q['display'], {
        'numCard': '24100027499297',
        'offerLabel': 'Access',
        'amount': 5000,
        'currency': 'XOF',
        'isRenewal': true,
      });

      final before = db.balance;
      final notifs = db.notifications.length;
      final r = await confirm(q, 'tv-subscription', 'ref-tv-1');
      expect(r['status'], 'SUCCESS');
      expect(r['completed'], isTrue);
      expect(db.balance, before - 5100);
      final op = db.operationById(r['operationId'] as String)!;
      expect(op['type'], 'ADDON_SALE');
      expect((op['service'] as Map)['slug'], 'merchant:addon:sell-tv-subscription:from-card');
      expect(db.operations.first['id'], op['id']);
      expect(db.issuerTransactions.first['transactionDesc'], 'Canal+ Access');
      expect(db.notifications.length, notifs + 1);
      expect(db.notifications.first['title'], 'Abonnement Canal+ activé');
      expect(db.notifications.first['linkId'], op['id']);
      expect(db.operationDetails[op['id']]!['movements'], isNotEmpty);
    });

    test('TV : changement de bouquet (durée obligatoire, options, combinaison) puis bouquet en cours', () async {
      final noDuration = await quote('tv-subscription', {'numCard': '24100027499297', 'mainOffer': 'EVASION'});
      expect(noDuration['feasible'], isFalse);
      expect(noDuration['reason'], 'Choisissez une durée pour ce bouquet avant de poursuivre.');
      expect((noDuration['checks'] as List).single, containsPair('key', 'duration'));

      final badOption = await quote('tv-subscription', {
        'numCard': '24100027499297',
        'mainOffer': 'TOUT_CANAL',
        'duration': '3',
        'optionsList': 'ENGLISH',
      });
      expect(badOption['feasible'], isFalse);
      expect(badOption['reason'], startsWith('Cette combinaison bouquet, durée et options n’est pas disponible'));

      final q = await quote('tv-subscription', {
        'numCard': '24100027499297',
        'mainOffer': 'EVASION',
        'duration': '3',
        'optionsList': 'CHR',
      });
      expect(q['feasible'], isTrue);
      expect(q['amount'], (10000 + 3000) * 3);
      expect(q['display'], containsPair('isRenewal', false));
      expect(q['display'], containsPair('duration', '3 mois'));
      expect(q['display'], containsPair('options', 'Charme'));
      await confirm(q, 'tv-subscription', 'ref-tv-2');

      final current = await c.get('/catalog/lookup/tv/24100027499297/current');
      expect((current.json['data'] as Map)['mainOfferLabel'], 'EVASION');
    });

    test('TV : contrat d’entrée et carte non vérifiable', () async {
      final bad = await c.post('/catalog/quote', {
        'service': 'tv-subscription',
        'funding': card(),
        'input': {'numCard': '24-100'},
      });
      expect(bad.status, 400);
      expect(bad.code, 'REQUEST_REJECTED');
      expect(
        bad.message,
        'Données invalides pour le service « tv-subscription » — input.numCard : numCard : lettres et chiffres uniquement.',
      );
      final unknown = await quote('tv-subscription', {'numCard': '24100027490000'});
      expect(unknown['feasible'], isFalse);
      expect((unknown['checks'] as List).single, containsPair('key', 'numCard'));
    });

    test('facture : toutes les impayées par défaut, puis plus rien à régler', () async {
      final q = await quote('electricity-postpaid', {'customerReference': '610201551642KA'});
      expect(q['feasible'], isTrue);
      expect(q['amount'], 9800 + 12500 + 11200);
      expect(q['amountDebited'], 33500 + 100);
      final display = q['display'] as Map;
      expect(display['customerName'], 'KOSSI ADJOVI');
      expect(display['totalDue'], 33500);
      expect(display['remainingUnpaid'], 0);
      expect((display['invoices'] as List).first, {
        'reference': 'FAC-2026-08-014',
        'amount': 9800,
        'period': '08/2026',
      });

      final r = await confirm(q, 'electricity-postpaid', 'ref-bill-1');
      expect(r['status'], 'SUCCESS');
      final op = db.operationById(r['operationId'] as String)!;
      expect(op['type'], 'ADDON_SALE');
      expect((op['parties'] as List).single, containsPair('channelLabel', 'SBEE'));
      expect(db.issuerTransactions.first['transactionDesc'], 'SBEE Facture 610201551642KA');
      expect(db.notifications.first['title'], 'Facture d’électricité réglée');

      final after = await c.get('/catalog/lookup/electricity/610201551642KA/invoices');
      expect((after.json['data'] as Map)['invoices'], isEmpty);
      final again = await quote('electricity-postpaid', {'customerReference': '610201551642KA'});
      expect(again['feasible'], isFalse);
      expect(again['reason'], 'Aucune facture impayée pour cet abonné : il n’y a rien à régler.');
    });

    test('facture : sélection (invoiceReferences), reste impayé, facture déjà réglée', () async {
      final q = await quote('electricity-postpaid', {
        'customerReference': '610201551642KA',
        'invoiceReferences': ['FAC-2026-09-001'],
      });
      expect(q['amount'], 12500);
      expect((q['display'] as Map)['remainingUnpaid'], 21000);
      await confirm(q, 'electricity-postpaid', 'ref-bill-2');

      final paid = await quote('electricity-postpaid', {
        'customerReference': '610201551642KA',
        'invoiceReferences': ['FAC-2026-09-001'],
      });
      expect(paid['feasible'], isFalse);
      expect(paid['reason'], startsWith('Facture(s) déjà réglée(s) ou introuvable(s) : FAC-2026-09-001.'));

      final contract = await c.post('/catalog/quote', {
        'service': 'electricity-postpaid',
        'funding': card(),
        'input': {'customerReference': '610201551642KA', 'invoiceReferences': 'FAC-2026-08-014'},
      });
      expect(contract.code, 'REQUEST_REJECTED');
      expect(contract.message, contains('input.invoiceReferences'));
      final unknown = await quote('electricity-postpaid', {'customerReference': '61020150000'});
      expect(unknown['feasible'], isFalse);
      expect((unknown['checks'] as List).single, containsPair('key', 'customerReference'));
    });
  });

  group('parcours (flux)', () {
    late ClockDb db;
    late ProviderContainer container;

    setUp(() async {
      db = ClockDb();
      final env = await TestEnv.create(signedIn: true, db: db);
      container = ProviderContainer(
        overrides: [...env.overrides, paymentClockProvider.overrideWithValue(() => db.now())],
      );
      container.listen(paymentFlowProvider, (_, _) {});
      await TestEnv.waitForAuth(container);
    });

    tearDown(() => container.dispose());

    test('buildRequest TV : reconduction sans mainOffer, changement avec durée et options', () {
      final config = serviceConfig(ServiceType.tv);
      expect(validateForm(config, {'numCard': '2410 0027 4992 97'}, const FormSelection()), isEmpty);
      expect(validateForm(config, {'numCard': '24-10'}, const FormSelection()), {
        'numCard': 'Lettres et chiffres uniquement, 8 à 20 caractères.',
      });
      expect(validateForm(config, {'numCard': '24100027499297', 'mainOffer': 'EVASION'}, const FormSelection()), {
        'duration': 'Choisissez une durée pour ce bouquet.',
      });

      final renew = buildRequest(config, {'numCard': '2410 0027 4992 97'}, const FormSelection(), cardCustomerId: 'c1');
      expect(renew.path.name, 'catalogCard');
      expect(renew.funding, {
        'source': 'CUSTOMER_CARD',
        'card': {'cardCustomerId': 'c1'},
      });
      expect(renew.input, {'numCard': '24100027499297'});

      final change = buildRequest(
        config,
        {'numCard': '24100027499297', 'mainOffer': 'EVASION', 'duration': '3', 'optionsList': 'CHR,ENGLISH'},
        const FormSelection(),
        cardCustomerId: 'c1',
      );
      expect(change.input, {
        'numCard': '24100027499297',
        'mainOffer': 'EVASION',
        'duration': '3',
        'optionsList': 'CHR,ENGLISH',
      });
    });

    test('buildRequest facture : toutes (sans invoiceReferences) ou sélection', () {
      final config = serviceConfig(ServiceType.elecBill);
      expect(validateForm(config, {}, const FormSelection()), {
        'customerReference': 'Référence client SBEE : champ obligatoire.',
      });
      final all = buildRequest(
        config,
        {'customerReference': ' 610201551642KA ', 'invoiceReferences': ''},
        const FormSelection(),
        cardCustomerId: 'c1',
      );
      expect(all.input, {'customerReference': '610201551642KA'});
      final some = buildRequest(
        config,
        {'customerReference': '610201551642KA', 'invoiceReferences': 'FAC-2026-08-014,FAC-2026-09-001'},
        const FormSelection(),
        cardCustomerId: 'c1',
      );
      expect(some.input, {
        'customerReference': '610201551642KA',
        'invoiceReferences': ['FAC-2026-08-014', 'FAC-2026-09-001'],
      });
    });

    test('facture : devis (montant imposé = somme) puis PIN → reçu', () async {
      final flow = container.read(paymentFlowProvider.notifier);
      final request = buildRequest(
        serviceConfig(ServiceType.elecBill),
        {'customerReference': '610201551642KA', 'invoiceReferences': 'FAC-2026-10-007'},
        const FormSelection(),
        cardCustomerId: db.sessionCardId,
      );
      expect(await flow.requestQuote(request), isNull);
      final quote = container.read(paymentFlowProvider).quote!;
      expect(quote.amount, 11200);
      expect(quote.amountDebited, 11300);
      expect(await flow.submitSecret('482915'), SecretOutcome.submitted);
      expect(container.read(paymentFlowProvider).execution!.completed, isTrue);
      final op = await flow.refreshOperation();
      expect(op!.status, OperationStatus.success);
      expect(op.service, ServiceType.elecBill);
    });
  });

  group('écrans', () {
    Future<(ClockDb, ProviderContainer)> setUpScreen(WidgetTester tester) async {
      final db = ClockDb();
      final env = await TestEnv.create(signedIn: true, db: db);
      final container = paymentContainer(env, overrides: [paymentClockProvider.overrideWithValue(() => db.now())]);
      addTearDown(container.dispose);
      await tester.runAsync(() => TestEnv.waitForAuth(container));
      return (db, container);
    }

    testWidgets('TV : carte inconnue → service partenaire indisponible', (tester) async {
      final (_, container) = await setUpScreen(tester);
      await pumpRouted(tester, container, Routes.service(ServiceType.tv));
      await pumpFrames(tester);
      expect(find.text('Abonnement TV'), findsOneWidget);
      expect(find.text('Vérifier l’abonnement'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('field-numCard')), '24100');
      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);
      expect(find.text('Lettres et chiffres uniquement, 8 à 20 caractères.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('field-numCard')), '24100027490000');
      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);
      expect(
        find.text('Service partenaire indisponible — vérifiez le numéro de carte TV et réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('TV : abonnement en cours → changement de bouquet → devis', (tester) async {
      final (_, container) = await setUpScreen(tester);
      await pumpRouted(tester, container, Routes.service(ServiceType.tv));
      await pumpFrames(tester);

      await tester.enterText(find.byKey(const Key('field-numCard')), '2410 0027 4992 97');
      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);
      expect(find.text('Bouquet en cours'), findsOneWidget);
      expect(find.text('ACCESS'), findsWidgets);
      expect(find.text(formatFcfa(5000)), findsOneWidget);
      expect(find.text('Voir le prix exact'), findsOneWidget);

      await tester.tap(find.byKey(const Key('option-change')));
      await pumpFrames(tester);
      expect(find.text('Tout Canal+'), findsOneWidget);
      // Le libellé du bouquet en cours vient désormais des offres.
      expect(find.text('Access'), findsWidgets);

      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);
      expect(find.text('Choisissez un bouquet.'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('option-EVASION')));
      await tester.tap(find.byKey(const Key('option-EVASION')));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);
      expect(find.text('Choisissez une durée pour ce bouquet.'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('option-3')));
      await tester.tap(find.byKey(const Key('option-3')));
      await tester.ensureVisible(find.byKey(const Key('tv-option-CHR')));
      await tester.tap(find.byKey(const Key('tv-option-CHR')));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);

      expect(find.text('Récapitulatif'), findsOneWidget);
      expect(find.text('Nouveau bouquet'), findsOneWidget);
      expect(find.text('Évasion'), findsOneWidget);
      expect(find.text('3 mois'), findsOneWidget);
      expect(find.text('Charme'), findsOneWidget);
      expect(find.text(formatFcfa(39000)), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('quote-total'))).data, formatFcfa(39100));
      final input = container.read(paymentFlowProvider).request!.input;
      expect(input, {'numCard': '24100027499297', 'mainOffer': 'EVASION', 'duration': '3', 'optionsList': 'CHR'});
    });

    testWidgets('TV : reconduction → devis sans mainOffer', (tester) async {
      final (_, container) = await setUpScreen(tester);
      await pumpRouted(tester, container, Routes.service(ServiceType.tv));
      await pumpFrames(tester);
      await tester.enterText(find.byKey(const Key('field-numCard')), '24100027491111');
      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);
      expect(find.text('EVASION'), findsWidgets);
      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);
      expect(find.text('Récapitulatif'), findsOneWidget);
      expect(find.text('Reconduction'), findsOneWidget);
      expect(container.read(paymentFlowProvider).request!.input, {'numCard': '24100027491111'});
    });

    testWidgets('facture : factures cochées par défaut, sélection → devis', (tester) async {
      final (_, container) = await setUpScreen(tester);
      await pumpRouted(tester, container, Routes.service(ServiceType.elecBill));
      await pumpFrames(tester);
      await tester.enterText(find.byKey(const Key('field-customerReference')), '610201551642KA');
      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);
      expect(find.text('KOSSI ADJOVI'), findsOneWidget);
      expect(find.text('Facture 09/2026'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('bill-total'))).data, formatFcfa(33500));

      await tester.tap(find.byKey(const Key('invoice-FAC-2026-08-014')));
      await pumpFrames(tester);
      expect(tester.widget<Text>(find.byKey(const Key('bill-total'))).data, formatFcfa(23700));
      await tester.tap(find.byKey(const Key('quote-submit')));
      await pumpFrames(tester);
      expect(find.text('Récapitulatif'), findsOneWidget);
      expect(find.text('Restera impayé'), findsOneWidget);
      expect(container.read(paymentFlowProvider).request!.input, {
        'customerReference': '610201551642KA',
        'invoiceReferences': ['FAC-2026-09-001', 'FAC-2026-10-007'],
      });
    });
  });
}
