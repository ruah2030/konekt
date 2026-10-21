import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/providers/ticker.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
import 'package:konekt/features/card/data/card_repository.dart';
import 'package:konekt/features/card/domain/card_models.dart';
import 'package:konekt/features/card/presentation/providers/secure_display_controller.dart';
import 'package:konekt/features/card/presentation/screens/secure_display_screen.dart';

import '../../helpers/test_app.dart';

/// Horloge pilotée par le test (remplace le ticker 1 s).
final testClockProvider = NotifierProvider<TestClock, DateTime>(TestClock.new);

class TestClock extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();
  void advance(Duration d) => state = state.add(d);
}

/// Compte les appels à `authorize`.
class CountingCardRepository extends CardRepository {
  CountingCardRepository(super.dio);
  final urls = <Uri>[];

  @override
  Future<DisplayAuthorization> authorizeDisplay(String cardCustomerId) async {
    final a = await super.authorizeDisplay(cardCustomerId);
    urls.add(a.displayUrl);
    return a;
  }
}

void main() {
  Future<(TestEnv, ProviderContainer, CountingCardRepository)> pump(
    WidgetTester tester, {
    String status = 'Active',
    bool fakeView = true,
    ValueNotifier<bool>? visible,
  }) async {
    final shown = visible ?? ValueNotifier(true);
    final env = await TestEnv.create(signedIn: true, db: FakeDb(cardStatus: status, hasPin: true));
    late CountingCardRepository repo;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          nowProvider.overrideWith((ref) => ref.watch(testClockProvider)),
          cardRepositoryProvider.overrideWith((ref) => repo = CountingCardRepository(ref.watch(dioProvider))),
          if (fakeView)
            cardDisplayViewBuilderProvider.overrideWithValue(
              (_, url) => Text('VUE ${url.queryParameters['t']}', key: const Key('fake-view')),
            ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(useGoogleFonts: false),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (_, v, _) => v ? const SecureDisplayScreen() : const Scaffold(body: Text('Ailleurs')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final container = ProviderScope.containerOf(tester.element(find.byType(SecureDisplayScreen)));
    container.read(cardRepositoryProvider);
    return (env, container, repo);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('authorize au tap seulement → vue → compte à rebours → expiration → afficher à nouveau', (tester) async {
    final (_, container, repo) = await pump(tester);

    // Aucune autorisation tant que « Afficher » n'est pas tapé.
    expect(find.byKey(const Key('display-intro')), findsOneWidget);
    expect(repo.urls, isEmpty);
    expect(find.byKey(const Key('fake-view')), findsNothing);

    await tester.tap(find.byKey(const Key('display-show')));
    await settle(tester);
    expect(repo.urls, hasLength(1));
    expect(find.byKey(const Key('fake-view')), findsOneWidget);
    expect(find.text('VUE ${repo.urls.single.queryParameters['t']}'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('display-countdown'))).data, matches(RegExp(r'^(1:00|0:59)$')));

    container.read(testClockProvider.notifier).advance(const Duration(seconds: 30));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('display-countdown'))).data, matches(RegExp(r'^0:(29|30)$')));
    expect(find.byKey(const Key('fake-view')), findsOneWidget);

    // Expiration : la vue est retirée (WebView détruite).
    container.read(testClockProvider.notifier).advance(const Duration(seconds: 31));
    await tester.pump();
    expect(find.byKey(const Key('fake-view')), findsNothing);
    expect(find.text('Affichage expiré'), findsOneWidget);
    expect(container.read(secureDisplayProvider), isA<SecureDisplayExpired>());
    expect(repo.urls, hasLength(1));

    // Nouvel appel authorize, nouvelle adresse.
    await tester.tap(find.byKey(const Key('display-again')));
    await settle(tester);
    expect(repo.urls, hasLength(2));
    expect(repo.urls[1], isNot(repo.urls[0]));
    expect(find.text('VUE ${repo.urls[1].queryParameters['t']}'), findsOneWidget);
  });

  testWidgets('faux backend : panneau de démonstration à la place de la page VGS', (tester) async {
    final (env, _, _) = await pump(tester, fakeView: false);
    await tester.tap(find.byKey(const Key('display-show')));
    await settle(tester);
    expect(find.byKey(const Key('display-demo')), findsOneWidget);
    expect(find.text('4532 1180 7741 ${env.db.last4}'), findsOneWidget);
    expect(find.text('Expiration'), findsOneWidget);
    expect(find.text('CVV'), findsOneWidget);
  });

  testWidgets('carte suspendue : affichage possible', (tester) async {
    final (_, _, repo) = await pump(tester, status: 'Inactive');
    await tester.tap(find.byKey(const Key('display-show')));
    await settle(tester);
    expect(repo.urls, hasLength(1));
    expect(find.byKey(const Key('fake-view')), findsOneWidget);
  });

  testWidgets('plafond atteint (403) : message et bouton désactivé', (tester) async {
    final (_, _, repo) = await pump(tester);
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await repo.authorizeDisplay('121436474');
      }
    });
    await tester.tap(find.byKey(const Key('display-show')));
    await settle(tester);
    expect(find.text('Cette carte a été consultée trop de fois aujourd’hui. Réessayez demain.'), findsOneWidget);
    expect(find.byKey(const Key('display-retry')), findsNothing);
    final button = tester.widget<FilledButton>(find.byKey(const Key('display-show-disabled')));
    expect(button.onPressed, isNull);
  });

  testWidgets('carte perdue : pas d’affichage, support', (tester) async {
    final (_, _, repo) = await pump(tester, status: 'LostOrStolen');
    await settle(tester);
    expect(find.byKey(const Key('display-show')), findsNothing);
    expect(find.byKey(const Key('display-support')), findsOneWidget);
    expect(repo.urls, isEmpty);
  });

  testWidgets('quitter l’écran efface l’autorisation', (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final (_, container, _) = await pump(tester, visible: visible);
    await tester.tap(find.byKey(const Key('display-show')));
    await settle(tester);
    expect(container.read(secureDisplayProvider), isA<SecureDisplayShown>());
    visible.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.exists(secureDisplayProvider), isFalse);
  });
}
