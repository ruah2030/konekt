import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:konekt/app/app.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/core/network/fake/fake_api.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/storage/app_prefs.dart';
import 'package:konekt/core/storage/secure_store.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Environnement de test : faux backend sans latence, stockage en mémoire.
class TestEnv {
  TestEnv._(this.db, this.api, this.store, this.prefs);

  /// [signedIn] : une session valide est déjà enregistrée (écrans protégés).
  static Future<TestEnv> create({FakeDb? db, bool signedIn = false, Map<String, Object> prefs = const {}}) async {
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR');
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final d = db ?? FakeDb();
    final api = FakeApi(db: d, latency: Duration.zero);
    final store = InMemorySecureStore();
    if (signedIn) {
      final t = d.issueTokens();
      await store.saveTokens(access: t.access, refresh: t.refresh);
    }
    return TestEnv._(d, api, store, AppPrefs(p));
  }

  final FakeDb db;
  final FakeApi api;
  final InMemorySecureStore store;
  final AppPrefs prefs;

  List<Override> get overrides => [
    fakeApiProvider.overrideWithValue(api),
    secureStoreProvider.overrideWithValue(store),
    appPrefsProvider.overrideWithValue(prefs),
  ];

  ProviderContainer container() => ProviderContainer(overrides: overrides);

  /// Application complète (routeur réel).
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(overrides: overrides, child: const KonektApp(useGoogleFonts: false)));
    await tester.pump();
  }

  /// Un écran isolé (sans routeur), avec le thème Konekt.
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.light(useGoogleFonts: false),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: screen,
        ),
      ),
    );
    await tester.pump();
  }
}
