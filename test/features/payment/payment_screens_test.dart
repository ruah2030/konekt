import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/domain/service_type.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/features/payment/presentation/providers/payment_flow.dart';
import 'package:konekt/features/payment/presentation/screens/processing_screen.dart';
import 'package:konekt/features/payment/presentation/screens/service_form_screen.dart';

import '../../helpers/test_app.dart';
import 'payment_test_utils.dart';

void main() {
  testWidgets('formulaire : validations locales puis devis', (tester) async {
    final env = await TestEnv.create(signedIn: true, db: ClockDb());
    final container = paymentContainer(env);
    addTearDown(container.dispose);
    await pumpRouted(tester, container, Routes.service(ServiceType.payout));
    await tester.pumpAndSettle();

    expect(find.text('Retirer vers Mobile Money'), findsOneWidget);
    expect(find.text("Rien n'est débité à cette étape."), findsOneWidget);
    expect(find.text('Solde disponible : ${formatFcfa(152400)}'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quote-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Choisissez : opérateur.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('option-mtn')));
    await tester.pump();
    expect(find.text('Choisissez : opérateur.'), findsNothing);
    await tester.tap(find.byKey(const Key('quote-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Numéro du portefeuille : champ obligatoire.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-msisdn')), '12');
    await tester.enterText(find.byKey(const Key('field-amount')), '5000');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Numéro de téléphone invalide.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-msisdn')), '+229 01 97 00 00 18');
    await tester.enterText(find.byKey(const Key('field-amount')), '50');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Montant minimum : 100 FCFA.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-amount')), '10 000');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await pumpFrames(tester);
    expect(find.text('Récapitulatif'), findsOneWidget);
    expect(find.text('Le bénéficiaire reçoit'), findsOneWidget);
    expect(find.text(formatFcfa(10220)), findsWidgets);
    expect(find.textContaining('nom non vérifié'), findsOneWidget);
    expect(find.text('Confirmer le paiement'), findsOneWidget);
  });

  testWidgets('formulaire : erreur serveur (solde insuffisant)', (tester) async {
    final env = await TestEnv.create(signedIn: true, db: ClockDb());
    final container = paymentContainer(env);
    addTearDown(container.dispose);
    await pumpRouted(tester, container, Routes.service(ServiceType.cash));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-amount')), '200000');
    await tester.tap(find.byKey(const Key('quote-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Solde insuffisant : il manque'), findsOneWidget);
    expect(find.textContaining('INSUFFICIENT_FUNDS'), findsOneWidget);
  });

  testWidgets('formulaire forfait : forfaits chargés depuis l’API', (tester) async {
    final env = await TestEnv.create(signedIn: true, db: ClockDb());
    usePhoneSize(tester);
    await env.pumpScreen(tester, const ServiceFormScreen(type: ServiceType.data));
    await tester.pumpAndSettle();
    expect(find.text('12 Go'), findsOneWidget);
    expect(find.text(formatFcfa(6000)), findsOneWidget);
    expect(find.text('Solde disponible : ${formatFcfa(152400)}'), findsNothing);
  });

  testWidgets('devis expiré → « Refaire le devis »', (tester) async {
    final db = ClockDb()..advance(const Duration(minutes: -11));
    final env = await TestEnv.create(signedIn: true, db: db);
    final container = paymentContainer(env);
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(paymentFlowProvider.notifier).requestQuote(ServiceType.cash, {'amount': '5000'}, null),
    );
    await pumpRouted(tester, container, Routes.quote);
    await pumpFrames(tester, count: 3);

    expect(find.text('Prix expiré'), findsOneWidget);
    expect(find.text('Prix expiré · Refaire le devis'), findsOneWidget);
    expect(find.text('Confirmer le paiement'), findsNothing);

    db.clock = DateTime.now();
    await tester.tap(find.byKey(const Key('quote-refresh')));
    await pumpFrames(tester, count: 3);
    expect(find.text('Confirmer le paiement'), findsOneWidget);
    expect(find.textContaining('Prix garanti · '), findsOneWidget);
  });

  testWidgets('PIN : code faux → erreur et saisie vidée ; verrouillage', (tester) async {
    final db = ClockDb();
    final env = await TestEnv.create(signedIn: true, db: db);
    final container = paymentContainer(env);
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(paymentFlowProvider.notifier).requestQuote(ServiceType.cash, {'amount': '5000'}, null),
    );
    await pumpRouted(tester, container, Routes.payPin);
    await pumpFrames(tester, count: 2);
    expect(find.text('Confirmer le paiement'), findsOneWidget);
    expect(find.text('Retrait au guichet · ${formatFcfa(5050)}'), findsOneWidget);

    Future<void> typePin(String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.byKey(Key('key-$d')));
        await tester.pump();
      }
      await pumpFrames(tester, count: 3);
    }

    await typePin('111111');
    expect(find.text('Code secret incorrect. 4 essai(s) avant verrouillage.'), findsOneWidget);
    expect(find.text('●'), findsNothing);

    db.pinTries = 1;
    await typePin('111111');
    expect(find.text('Paiements verrouillés'), findsOneWidget);
    expect(find.textContaining('Réessayez dans 15 minute(s)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('key-4')));
    await tester.pump();
    expect(find.text('●'), findsNothing);

    await tester.tap(find.byKey(const Key('pay-pin-forgot')));
    await pumpFrames(tester, count: 3);
    expect(find.text('PIN RESET'), findsOneWidget);
  });

  testWidgets('PIN correct → traitement → reçu', (tester) async {
    final db = ClockDb();
    final env = await TestEnv.create(signedIn: true, db: db);
    final container = paymentContainer(
      env,
      overrides: [paymentPollIntervalProvider.overrideWithValue(const Duration(milliseconds: 200))],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(paymentFlowProvider.notifier).requestQuote(ServiceType.topup, {
        'msisdn': '+22901960000',
        'amount': '20000',
      }, 'mtn'),
    );
    await pumpRouted(tester, container, Routes.payPin);
    await pumpFrames(tester, count: 2);
    for (final d in '482915'.split('')) {
      await tester.tap(find.byKey(Key('key-$d')));
      await tester.pump();
    }
    await pumpFrames(tester, count: 5);
    expect(find.text('Paiement en cours'), findsOneWidget);
    expect(find.text('Demande envoyée à MTN MoMo'), findsOneWidget);
    expect(find.text('Carte créditée'), findsOneWidget);

    db.advance(const Duration(seconds: 2));
    await pumpFrames(tester, count: 6);
    expect(find.text('Validez sur votre téléphone'), findsOneWidget);
    expect(find.textContaining('Une demande de ${formatFcfa(20200)} est arrivée sur MTN MoMo'), findsOneWidget);

    db.advance(const Duration(seconds: 5));
    await pumpFrames(tester, count: 8);
    expect(find.text('Paiement réussi'), findsOneWidget);
    expect(find.text(formatSignedFcfa(20000)), findsOneWidget);
    expect(db.balance, 172400);

    await tester.tap(find.byKey(const Key('receipt-done')));
    await pumpFrames(tester, count: 3);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('reçu électricité : code mis en avant et copiable', (tester) async {
    final db = ClockDb();
    db.operations.insert(0, {
      'id': 'op_ELEC',
      'service': 'elec',
      'title': 'Électricité prépayée',
      'status': 'SUCCESS',
      'step': 'SUCCESS',
      'amount': 5000,
      'fee': 125,
      'total': 5125,
      'direction': 'DEBIT',
      'beneficiary': 'Compteur 12345678901',
      'extra': [
        {
          'label': 'Code de recharge à saisir sur le compteur',
          'value': '4821 0937 5520 1184 6653',
          'note': 'Aussi envoyé par WhatsApp',
        },
      ],
      'createdAt': db.now().toIso8601String(),
    });
    final env = await TestEnv.create(signedIn: true, db: db);
    final container = paymentContainer(env);
    addTearDown(container.dispose);
    await pumpRouted(tester, container, Routes.receipt('op_ELEC'));
    await tester.pumpAndSettle();

    expect(find.text('Paiement réussi'), findsOneWidget);
    expect(find.text(formatSignedFcfa(-5125)), findsOneWidget);
    expect(find.text('Code de recharge à saisir sur le compteur'), findsOneWidget);
    expect(find.text('4821 0937 5520 1184 6653'), findsOneWidget);
    expect(find.text('Aussi envoyé par WhatsApp'), findsOneWidget);
    expect(find.text('Compteur 12345678901'), findsOneWidget);
    expect(find.text('op_ELEC'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byKey(const Key('receipt-copy')));
    await pumpFrames(tester, count: 4);
    expect(find.text('Code copié.'), findsOneWidget);
    expect(copied, '48210937552011846653');
  });

  testWidgets('reçu échoué : motif affiché', (tester) async {
    final env = await TestEnv.create(signedIn: true, db: ClockDb());
    final container = paymentContainer(env);
    addTearDown(container.dispose);
    await pumpRouted(tester, container, Routes.receipt('op_6H1M'));
    await tester.pumpAndSettle();
    expect(find.text('Paiement échoué'), findsOneWidget);
    expect(find.text('Motif'), findsOneWidget);
    expect(find.text("Portefeuille introuvable. Votre carte n'a pas été débitée."), findsOneWidget);
  });
}
