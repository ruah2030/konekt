import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/card.dart';
import 'package:konekt/core/domain/promotion.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/account/presentation/account_providers.dart';
import 'package:konekt/features/promotions/presentation/promo_actions.dart';
import 'package:konekt/features/promotions/presentation/promo_slot.dart';

import '../../helpers/test_app.dart';

Future<void> settle(WidgetTester tester, [int frames = 5]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<TestEnv> pumpSlot(WidgetTester tester, PromoPlacement placement, {FakeDb? db}) async {
  final env = await TestEnv.create(signedIn: true, db: db);
  await env.pumpScreen(
    tester,
    Scaffold(
      // La carte est chargée comme sur l'accueil (openService lit son statut).
      body: Consumer(
        builder: (_, ref, child) {
          ref
            ..watch(cardProvider)
            ..watch(serviceOffersProvider);
          return child!;
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PromoSlot(placement: placement),
        ),
      ),
    ),
  );
  await settle(tester);
  return env;
}

void main() {
  group('promoUri', () {
    test('ajoute https si absent et refuse les cibles invalides', () {
      expect(promoUri('jumia.bj').toString(), 'https://jumia.bj');
      expect(promoUri('https://konekt.app/invite').toString(), 'https://konekt.app/invite');
      expect(promoUri(''), isNull);
      expect(promoUri('tel:123'), isNull);
    });
  });

  testWidgets('accueil : carrousel, points, rotation automatique', (tester) async {
    await pumpSlot(tester, PromoPlacement.home);

    expect(find.text('−10 % sur Jumia avec votre carte'), findsOneWidget);
    expect(find.text('OFFRE PARTENAIRE · ANNONCE'), findsOneWidget);
    expect(find.byKey(const Key('promo-dot-2')), findsOneWidget);

    // Rotation toutes les 5 s.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('12 Go pour 6 000 FCFA'), findsOneWidget);
    expect(find.text('−10 % sur Jumia avec votre carte'), findsNothing);

    // Point cliquable.
    await tester.tap(find.byKey(const Key('promo-dot-2')));
    await settle(tester);
    expect(find.text('Invitez un proche, gagnez 1 000 FCFA'), findsOneWidget);
  });

  testWidgets('accueil : fermer une publicité la masque et la persiste', (tester) async {
    final env = await pumpSlot(tester, PromoPlacement.home);

    await tester.tap(find.byKey(const Key('promo-dismiss-ad_jumia')));
    await settle(tester);
    expect(find.text('−10 % sur Jumia avec votre carte'), findsNothing);
    expect(find.text('12 Go pour 6 000 FCFA'), findsOneWidget);
    expect(env.prefs.dismissedPromos, ['ad_jumia']);
  });

  testWidgets('accueil : lien externe impossible à ouvrir → message', (tester) async {
    await pumpSlot(tester, PromoPlacement.home);
    await tester.tap(find.byKey(const Key('promo-ad_jumia')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(find.text(promoLinkErrorMessage), findsOneWidget);
  });

  testWidgets('reçu : première publicité en carte, fermeture', (tester) async {
    await pumpSlot(tester, PromoPlacement.receipt);

    expect(find.text("Payez l'électricité en 30 secondes"), findsOneWidget);
    expect(find.byKey(const Key('promo-carousel')), findsNothing);

    await tester.tap(find.byKey(const Key('promo-dismiss-ad_elec')));
    await settle(tester);
    expect(find.text("Payez l'électricité en 30 secondes"), findsNothing);
  });

  testWidgets('action service refusée si la carte est suspendue', (tester) async {
    await pumpSlot(tester, PromoPlacement.history, db: FakeDb(cardStatus: 'INACTIVE'));
    expect(find.text('Retrait au guichet sans frais'), findsOneWidget);
    await tester.tap(find.byKey(const Key('promo-ad_cash')));
    await settle(tester);
    expect(find.text(CardStatus.inactive.blockedMessage), findsOneWidget);
  });

  testWidgets('action service grisée au catalogue : motif, pas de parcours', (tester) async {
    await pumpSlot(tester, PromoPlacement.receipt, db: FakeDb(incident: true));
    await tester.tap(find.byKey(const Key('promo-ad_elec')));
    await settle(tester);
    expect(find.text('Momentanément indisponible — nos équipes travaillent au rétablissement.'), findsOneWidget);
  });

  testWidgets('publicités désactivées : rien n’est affiché', (tester) async {
    await pumpSlot(tester, PromoPlacement.home, db: FakeDb(adsEnabled: false));
    expect(find.byType(PromoCarousel), findsNothing);
    expect(find.textContaining('ANNONCE'), findsNothing);
  });

  testWidgets('publicités déjà masquées : ignorées', (tester) async {
    final env = await TestEnv.create(
      signedIn: true,
      prefs: {
        'dismissed_promos': ['ad_jumia', 'ad_data', 'ad_invite'],
      },
    );
    await env.pumpScreen(tester, const Scaffold(body: PromoSlot(placement: PromoPlacement.home)));
    await settle(tester);
    expect(find.byType(PromoCarousel), findsNothing);
  });
}
