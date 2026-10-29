import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:konekt/app/app.dart';
import 'package:konekt/core/domain/session.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/core/network/fake/fake_api.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/security/device_auth.dart';
import 'package:konekt/core/storage/app_prefs.dart';
import 'package:konekt/core/storage/secure_store.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';
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
      await store.saveTokens(session: t.session, refresh: t.refresh);
      await store.saveCardSession(
        CardSession(
          cardCustomerId: d.sessionCardId,
          last4: d.last4,
          firstName: d.holder['firstName'] as String,
          lastName: d.holder['lastName'] as String,
          hasPin: d.hasPin,
          isExternalCard: d.isExternalCard,
        ),
      );
    }
    return TestEnv._(d, api, store, AppPrefs(p));
  }

  final FakeDb db;
  final FakeApi api;
  final InMemorySecureStore store;
  final AppPrefs prefs;

  /// Déverrouillage du téléphone : indisponible par défaut (pas de plugin natif en test).
  DeviceAuth deviceAuth = const _NoDeviceAuth();

  List<Override> get overrides => [
    fakeApiProvider.overrideWithValue(api),
    secureStoreProvider.overrideWithValue(store),
    appPrefsProvider.overrideWithValue(prefs),
    deviceAuthProvider.overrideWithValue(deviceAuth),
  ];

  ProviderContainer container() => ProviderContainer(overrides: overrides);

  /// Application complète (routeur réel).
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(overrides: overrides, child: const KonektApp(useGoogleFonts: false)));
    await tester.pump();
  }

  /// Attend que la session soit restaurée (AuthState ≠ unknown) dans [c].
  static Future<void> waitForAuth(ProviderContainer c) async {
    c.read(authControllerProvider);
    for (var i = 0; i < 50 && c.read(authControllerProvider).status == AuthStatus.unknown; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
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

class _NoDeviceAuth implements DeviceAuth {
  const _NoDeviceAuth();

  @override
  Future<DeviceAuthResult> confirm(String reason) async => DeviceAuthResult.unavailable;
}
