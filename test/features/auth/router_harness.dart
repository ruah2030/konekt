import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:konekt/design_system/theme/app_theme.dart';

import '../../helpers/test_app.dart';

/// Taille d'écran de la maquette (412 × 892).
void usePhoneSize(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(412 * 3, 892 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Monte quelques écrans avec un vrai GoRouter (sans les redirections d'auth de l'app).
/// Les routes non fournies affichent leur chemin.
Future<ProviderContainer> pumpWithRouter(
  WidgetTester tester,
  TestEnv env, {
  required String initial,
  required Map<String, Widget Function()> screens,
}) async {
  final router = GoRouter(
    initialLocation: initial,
    routes: [for (final e in screens.entries) GoRoute(path: e.key, builder: (_, _) => e.value())],
    errorBuilder: (_, state) => Scaffold(body: Text('route:${state.uri.path}')),
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(overrides: env.overrides);
  addTearDown(container.dispose);
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
  return container;
}

/// Écran de destination factice.
Widget routeStub(String path) => Scaffold(body: Text('route:$path'));
