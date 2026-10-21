import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:dio/dio.dart';
import 'package:konekt/core/domain/service_type.dart';
import 'package:konekt/core/network/fake/fake_api.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/design_system/theme/app_theme.dart';
import 'package:konekt/features/history/presentation/screens/history_screen.dart';
import 'package:konekt/features/payment/presentation/screens/pay_pin_screen.dart';
import 'package:konekt/features/payment/presentation/screens/processing_screen.dart';
import 'package:konekt/features/payment/presentation/screens/quote_screen.dart';
import 'package:konekt/features/payment/presentation/screens/receipt_screen.dart';
import 'package:konekt/features/payment/presentation/screens/service_form_screen.dart';

import '../../helpers/test_app.dart';

/// Faux backend dont l'horloge est pilotée par le test.
class ClockDb extends FakeDb {
  ClockDb({super.cardStatus, super.hasPin = true});

  DateTime clock = DateTime.now();

  @override
  DateTime now() => clock;

  void advance(Duration d) => clock = clock.add(d);
}

/// Appels directs au faux backend (tests des handlers), avec un jeton de session valide.
class FakeClient {
  FakeClient(this.db) : api = FakeApi(db: db, latency: Duration.zero) {
    _token = db.issueTokens().session;
  }

  final FakeDb db;
  final FakeApi api;
  late final String _token;

  Future<FakeResponse> call(String method, String path, {Object? body, Map<String, dynamic>? query}) => api.handle(
    RequestOptions(
      method: method,
      path: path,
      data: body,
      queryParameters: query ?? const {},
      headers: {'Authorization': 'Bearer $_token'},
    ),
  );

  Future<FakeResponse> post(String path, [Object? body]) => call('POST', path, body: body);
  Future<FakeResponse> get(String path, [Map<String, dynamic>? query]) => call('GET', path, query: query);
}

extension FakeResponseRead on FakeResponse {
  Map<String, dynamic> get json => Map<String, dynamic>.from(body! as Map);
  String? get code => json['code'] as String?;
  String? get message => json['message'] as String?;
}

/// Routeur minimal avec les écrans du parcours de paiement et l'historique.
GoRouter paymentRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: Routes.home,
      builder: (_, _) => const Scaffold(body: Text('HOME')),
    ),
    GoRoute(path: Routes.history, builder: (_, _) => const HistoryScreen()),
    GoRoute(
      path: Routes.pinReset,
      builder: (_, _) => const Scaffold(body: Text('PIN RESET')),
    ),
    GoRoute(path: Routes.quote, builder: (_, _) => const QuoteScreen()),
    GoRoute(path: Routes.payPin, builder: (_, _) => const PayPinScreen()),
    GoRoute(path: Routes.processing, builder: (_, _) => const ProcessingScreen()),
    GoRoute(
      path: '/pay/:type',
      builder: (_, state) => ServiceFormScreen(type: ServiceType.tryParse(state.pathParameters['type'])!),
    ),
    GoRoute(
      path: '/receipt/:id',
      builder: (_, state) => ReceiptScreen(
        operationId: state.pathParameters['id']!,
        fromHistory: state.uri.queryParameters['from'] == 'history',
      ),
    ),
  ],
);

/// Conteneur partagé entre le test et l'arbre de widgets.
ProviderContainer paymentContainer(TestEnv env, {List<Override> overrides = const []}) =>
    ProviderContainer(overrides: [...env.overrides, ...overrides]);

/// Écran de téléphone (412 × 915) au lieu du 800 × 600 par défaut.
void usePhoneSize(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1236, 2745)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<GoRouter> pumpRouted(WidgetTester tester, ProviderContainer container, String location) async {
  usePhoneSize(tester);
  final router = paymentRouter(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(useGoogleFonts: false),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  return router;
}

/// Plusieurs frames courtes (timers périodiques actifs : horloge, spinner).
Future<void> pumpFrames(WidgetTester tester, {int count = 10, Duration step = const Duration(milliseconds: 50)}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(step);
  }
}
