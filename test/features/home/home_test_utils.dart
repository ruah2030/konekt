import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:konekt/design_system/theme/app_theme.dart';

import '../../helpers/test_app.dart';

/// Laisse le faux backend répondre sans `pumpAndSettle` (timers périodiques : publicités, pastille).
Future<void> settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Affiche [screen] dans un petit routeur : `/receipt/:id` et `/pay/:id` sont remplacés par des écrans
/// témoins (« Reçu {id} {from} », « Service {id} ») pour vérifier la navigation.
Future<void> pumpRouted(WidgetTester tester, TestEnv env, Widget screen, {List<Override> extra = const []}) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, _) => screen),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('Accueil témoin')),
      ),
      GoRoute(
        path: '/history',
        builder: (_, _) => const Scaffold(body: Text('Historique témoin')),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const Scaffold(body: Text('Notifications témoin')),
      ),
      GoRoute(
        path: '/receipt/:id',
        builder: (_, s) =>
            Scaffold(body: Text('Reçu ${s.pathParameters['id']} ${s.uri.queryParameters['from'] ?? ''}'.trim())),
      ),
      GoRoute(
        path: '/pay/:id',
        builder: (_, s) => Scaffold(body: Text('Service ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/card/display',
        builder: (_, _) => const Scaffold(body: Text('Ma carte témoin')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...env.overrides, ...extra],
      child: MaterialApp.router(
        theme: AppTheme.light(useGoogleFonts: false),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      ),
    ),
  );
  await settle(tester);
}
