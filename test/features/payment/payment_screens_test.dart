import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/domain/service_type.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/features/payment/domain/payment_models.dart';
import 'package:konekt/features/payment/domain/service_config.dart';
import 'package:konekt/features/payment/presentation/providers/payment_flow.dart';
import 'package:konekt/features/payment/presentation/screens/processing_screen.dart';

import '../../helpers/test_app.dart';
import 'payment_test_utils.dart';

void main() {
  Future<(ClockDb, ProviderContainer)> setUpFlow({ClockDb? clockDb}) async {
    final db = clockDb ?? ClockDb();
    final env = await TestEnv.create(signedIn: true, db: db);
    final container = paymentContainer(
      env,
      overrides: [
        paymentPollIntervalProvider.overrideWithValue(const Duration(milliseconds: 200)),
        paymentClockProvider.overrideWithValue(() => db.now()),
      ],
    );
    addTearDown(container.dispose);
    return (db, container);
  }

  Future<void> typeKeys(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.byKey(Key('key-$d')));
      await tester.pump();
    }
    await pumpFrames(tester, count: 6);
  }

  /// Devis préparé hors écran (Dio réel : `runAsync`).
  Future<void> prepare(
    WidgetTester tester,
    ProviderContainer c,
    ServiceType type,
    Map<String, String> values, [
    FormSelection s = const FormSelection(),
  ]) async {
    await tester.runAsync(() async {
      await TestEnv.waitForAuth(c);
      final request = buildRequest(serviceConfig(type), values, s, cardCustomerId: '121436474');
      final failure = await c.read(paymentFlowProvider.notifier).requestQuote(request);
      expect(failure, isNull);
    });
  }

  testWidgets('formulaire transfert : erreurs sous les champs, refus serveur, puis récapitulatif', (tester) async {
    final (_, container) = await setUpFlow();
    await pumpRouted(tester, container, Routes.service(ServiceType.transfer));
    await pumpFrames(tester);

    expect(find.text('Envoyer vers une carte'), findsOneWidget);
    expect(find.text("Rien n'est débité à cette étape."), findsOneWidget);
    expect(find.text('Solde disponible : ${formatFcfa(152400)}'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('Carte du bénéficiaire : champ obligatoire.'), findsOneWidget);
    expect(find.text('Montant (FCFA) : champ obligatoire.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-toCardCustomerId')), '999 999 999');
    await tester.enterText(find.byKey(const Key('field-amount')), '15000');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('Aucune carte ne correspond à l’identifiant 999999999.'), findsOneWidget);
    expect(find.textContaining('NOT_FOUND'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-toCardCustomerId')), '121 436 999');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('Récapitulatif'), findsOneWidget);
    expect(find.text('Afiavi Sossou · •••• 9034'), findsOneWidget);
    expect(find.text(formatFcfa(15440)), findsWidgets);
    expect(find.text('Vous payez'), findsOneWidget);
    expect(find.textContaining('Prix garanti · '), findsOneWidget);
  });

  testWidgets('forfait internet : offres de la ligne puis devis', (tester) async {
    final (_, container) = await setUpFlow();
    await pumpRouted(tester, container, Routes.service(ServiceType.data));
    await pumpFrames(tester);
    expect(find.text('Voir les offres'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-beneficiary')), '01 96 66 62 62');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('12 Go - 30 jours'), findsOneWidget);
    expect(find.text(formatFcfa(6000)), findsOneWidget);
    expect(find.text('Voir le prix exact'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('Choisissez : forfait.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('option-18490')));
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('Récapitulatif'), findsOneWidget);
    expect(find.text('5 Go - 30 jours'), findsOneWidget);
    expect(find.text('+2290196666262'), findsOneWidget);
  });

  testWidgets('électricité : devis refusé, contrôle en échec sous le champ', (tester) async {
    final (_, container) = await setUpFlow();
    await pumpRouted(tester, container, Routes.service(ServiceType.elec));
    await pumpFrames(tester);
    await tester.enterText(find.byKey(const Key('field-meterNum')), '01234560000');
    await tester.enterText(find.byKey(const Key('field-amount')), '5000');
    await tester.tap(find.byKey(const Key('option-whatsapp')));
    await tester.enterText(find.byKey(const Key('field-recipientContact')), 'awa@example');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('Numéro de téléphone invalide.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-recipientContact')), '+229 01 67 12 34 56');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.textContaining('Ce compteur n’a pas pu être vérifié.'), findsOneWidget);
    expect(find.text('Non reconnu par le fournisseur'), findsOneWidget);
  });

  testWidgets('devis expiré → « Refaire le devis »', (tester) async {
    final db = ClockDb()..advance(const Duration(minutes: -11));
    final (_, container) = await setUpFlow(clockDb: db);
    await prepare(tester, container, ServiceType.cash, {
      'amount': '5000',
      'deliveryChannel': 'SMS',
      'beneficiaryContact': '0167123456',
    });
    await pumpRouted(tester, container, Routes.quote);
    await pumpFrames(tester, count: 3);

    expect(find.text('Prix expiré'), findsOneWidget);
    expect(find.text('Prix expiré · Refaire le devis'), findsOneWidget);
    expect(find.text('Confirmer le paiement'), findsNothing);

    db.clock = DateTime.now();
    await tester.tap(find.byKey(const Key('quote-refresh')));
    await pumpFrames(tester, count: 3);
    expect(find.text('Confirmer le paiement'), findsOneWidget);
    expect(find.textContaining('Prix garanti · 9:'), findsOneWidget);
  });

  testWidgets('PIN faux : message du serveur, saisie vidée, lien « Code secret oublié ? »', (tester) async {
    final (_, container) = await setUpFlow();
    await prepare(tester, container, ServiceType.cash, {
      'amount': '5000',
      'deliveryChannel': 'SMS',
      'beneficiaryContact': '0167123456',
    });
    await pumpRouted(tester, container, Routes.payPin);
    await pumpFrames(tester, count: 2);
    expect(find.text('Confirmer le paiement'), findsOneWidget);
    expect(find.text('Retrait au guichet · ${formatFcfa(5100)}'), findsOneWidget);

    await typeKeys(tester, '111111');
    expect(find.text('Code incorrect — 4 tentative(s) restante(s).'), findsOneWidget);
    expect(find.text('●'), findsNothing);

    await tester.tap(find.byKey(const Key('pay-pin-forgot')));
    await pumpFrames(tester, count: 3);
    expect(find.text('PIN RESET'), findsOneWidget);
  });

  testWidgets('parcours complet : transfert → PIN → traitement → reçu', (tester) async {
    final (db, container) = await setUpFlow();
    await pumpRouted(tester, container, Routes.service(ServiceType.transfer));
    await pumpFrames(tester);
    await tester.enterText(find.byKey(const Key('field-toCardCustomerId')), '121436999');
    await tester.enterText(find.byKey(const Key('field-amount')), '15000');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const Key('quote-confirm')));
    await pumpFrames(tester);
    expect(find.text('Code secret oublié ?'), findsOneWidget);

    await typeKeys(tester, '482915');
    await pumpFrames(tester, count: 10);
    expect(find.text('Paiement réussi'), findsOneWidget);
    expect(find.text(formatSignedFcfa(-15440)), findsOneWidget);
    expect(find.text('Afiavi Sossou · •••• 9034'), findsOneWidget);
    expect(find.textContaining('Réf. COP-'), findsOneWidget);
    expect(db.balance, 152400 - 15440);

    await tester.tap(find.byKey(const Key('receipt-done')));
    await pumpFrames(tester, count: 3);
    expect(find.text('HOME'), findsOneWidget);
    expect(container.read(paymentFlowProvider).quote, isNull);
  });

  testWidgets('quitter le récapitulatif annule l’opération carte initiée', (tester) async {
    final (db, container) = await setUpFlow();
    await pumpRouted(tester, container, Routes.service(ServiceType.transfer));
    await pumpFrames(tester);
    await tester.enterText(find.byKey(const Key('field-toCardCustomerId')), '121436999');
    await tester.enterText(find.byKey(const Key('field-amount')), '15000');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    final id = container.read(paymentFlowProvider).quote!.operationId!;
    await tester.tap(find.byKey(const Key('quote-edit')));
    await pumpFrames(tester);
    expect(find.text('Envoyer vers une carte'), findsOneWidget);
    expect(db.operationById(id)!['status'], 'CANCELLED');
  });

  testWidgets('recharge MTN MoMo : validation sur le téléphone puis reçu', (tester) async {
    final (db, container) = await setUpFlow();
    await pumpRouted(tester, container, Routes.service(ServiceType.topup));
    await pumpFrames(tester);
    expect(find.text('Solde disponible : ${formatFcfa(152400)}'), findsNothing);
    await tester.tap(find.byKey(const Key('option-MOMO')));
    await pumpFrames(tester, count: 2);
    await tester.enterText(find.byKey(const Key('field-payerIdentifier')), '0196000062');
    await tester.enterText(find.byKey(const Key('field-amount')), '20000');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('Prénom du titulaire : champ obligatoire.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field-payerFirstName')), 'Awa');
    await tester.enterText(find.byKey(const Key('field-payerLastName')), 'Houngbédji');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('Total prélevé sur votre Mobile Money'), findsOneWidget);
    expect(find.text(formatFcfa(20500)), findsWidgets);

    await tester.tap(find.byKey(const Key('quote-confirm')));
    await pumpFrames(tester);
    expect(find.text('Validez sur votre téléphone'), findsOneWidget);
    expect(find.textContaining('Une demande de ${formatFcfa(20500)} est arrivée sur MTN Mobile Money'), findsOneWidget);
    expect(find.text('Demande envoyée à MTN Mobile Money'), findsOneWidget);

    db.advance(const Duration(seconds: 20));
    await pumpFrames(tester, count: 10);
    expect(find.text('Recharge réussie'), findsOneWidget);
    expect(find.text(formatSignedFcfa(20000)), findsOneWidget);
    expect(db.balance, 172400);
  });

  testWidgets('recharge B-MO : saisie du code sur l’écran de traitement', (tester) async {
    final (_, container) = await setUpFlow();
    const bmo = WalletChannel(slug: 'BMO', label: 'BestCash Money', holderVerification: true);
    await prepare(tester, container, ServiceType.topup, {
      'wallet': 'BMO',
      'payerIdentifier': '0196000062',
      'amount': '5000',
    }, const FormSelection(wallet: bmo));
    await pumpRouted(tester, container, Routes.quote);
    await pumpFrames(tester, count: 3);
    expect(find.textContaining('Vous recevrez un code de BestCash Money par SMS'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quote-confirm')));
    await pumpFrames(tester);
    expect(find.text('Saisissez le code reçu'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('funding-code')), '0000');
    await tester.tap(find.byKey(const Key('funding-submit')));
    await pumpFrames(tester);
    expect(find.text('Code refusé. 2 essai(s) restant(s).'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('funding-code')), '482913');
    await tester.tap(find.byKey(const Key('funding-submit')));
    await pumpFrames(tester, count: 10);
    expect(find.text('Recharge réussie'), findsOneWidget);
  });

  testWidgets('reçu depuis l’historique : opération échouée, motif et contrepartie', (tester) async {
    final (db, container) = await setUpFlow();
    final failed = db.operations.firstWhere((o) => o['status'] == 'FAILED');
    await pumpRouted(tester, container, Routes.receipt(failed['id'] as String, fromHistory: true));
    await pumpFrames(tester);
    expect(find.text('Paiement échoué'), findsOneWidget);
    expect(find.text('Motif'), findsOneWidget);
    expect(find.text("Portefeuille introuvable. Votre carte n'a pas été débitée."), findsOneWidget);
    expect(find.text('Moov Money · Afi M. · +22901****0018'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.ensureVisible(find.byKey(const Key('receipt-copy-ref')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('receipt-copy-ref')));
    await pumpFrames(tester, count: 3);
    expect(copied, failed['reference']);
  });
}
