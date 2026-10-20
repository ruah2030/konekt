import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/providers/ticker.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
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

void main() {
  Future<(TestEnv, ProviderContainer)> pump(
    WidgetTester tester, {
    String status = 'ACTIVE',
    ValueNotifier<bool>? visible,
  }) async {
    final shown = visible ?? ValueNotifier(true);
    final env = await TestEnv.create(signedIn: true, db: FakeDb(cardStatus: status));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...env.overrides, nowProvider.overrideWith((ref) => ref.watch(testClockProvider))],
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
    final container = ProviderScope.containerOf(tester.element(find.byType(SecureDisplayScreen)));
    return (env, container);
  }

  testWidgets('chargement → données → expiration après 60 s → afficher à nouveau', (tester) async {
    final (env, container) = await pump(tester);

    // Premier frame : ouverture en cours.
    expect(find.text('Ouverture sécurisée…'), findsOneWidget);
    expect(find.text("Affichage sécurisé de l'émetteur"), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Numéro de carte'), findsOneWidget);
    expect(find.text('4532 1180 7741 ${env.db.last4}'), findsOneWidget);
    expect(find.text('Expire fin'), findsOneWidget);
    expect(find.text('04/27'), findsOneWidget);
    expect(find.text('CVV'), findsOneWidget);
    expect(find.text('318'), findsOneWidget);
    expect(find.byKey(const Key('display-progress')), findsOneWidget);
    expect(
      find.text(
        "Lien à usage unique, valable une minute. Ne faites pas de capture d'écran et ne communiquez jamais votre CVV.",
      ),
      findsOneWidget,
    );

    // 30 s plus tard : toujours affiché, compte à rebours ~0:30.
    container.read(testClockProvider.notifier).advance(const Duration(seconds: 30));
    await tester.pump();
    expect(find.text('318'), findsOneWidget);
    final countdown = tester.widget<Text>(find.byKey(const Key('display-countdown'))).data!;
    expect(countdown, matches(RegExp(r'^0:(2\d|3[01])$')));

    // Au-delà de 60 s : données masquées et effacées de l'état.
    container.read(testClockProvider.notifier).advance(const Duration(seconds: 31));
    await tester.pump();
    expect(find.text('318'), findsNothing);
    expect(find.textContaining('4532'), findsNothing);
    expect(find.text('Affichage expiré'), findsOneWidget);
    expect(find.text('Pour votre sécurité, les données ont été masquées.'), findsOneWidget);
    expect(container.read(secureDisplayProvider), isA<SecureDisplayExpired>());

    // Nouvel affichage (nouveau délai de 60 s calculé par le serveur).
    container.read(testClockProvider.notifier).advance(const Duration(seconds: -61));
    await tester.tap(find.byKey(const Key('display-again')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('318'), findsOneWidget);
  });

  testWidgets('carte non active → message de blocage', (tester) async {
    await pump(tester, status: 'INACTIVE');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Cette carte est suspendue. Réactivez-la pour payer à nouveau.'), findsOneWidget);
    expect(find.text('318'), findsNothing);
    expect(find.byKey(const Key('display-retry')), findsNothing);
  });

  testWidgets('quitter l’écran efface les données', (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final (_, container) = await pump(tester, visible: visible);
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(secureDisplayProvider), isA<SecureDisplayShown>());
    visible.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.exists(secureDisplayProvider), isFalse);
  });
}
