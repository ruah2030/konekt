import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/app_prefs.dart';
import 'app.dart';
import 'startup_error_app.dart';

/// Démarrage de l'app. Rien ici ne doit pouvoir empêcher le premier affichage : chaque étape a un délai
/// maximal, et un échec affiche un écran d'erreur lisible au lieu de laisser le splash natif figé.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[Konekt] FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[Konekt] Erreur non gérée : $error\n$stack');
    return true;
  };

  try {
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR').timeout(_stepTimeout);
    // Non bloquant : l'orientation n'est pas indispensable au démarrage.
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]).timeout(_stepTimeout).catchError((_) {}),
    );
    final prefs = await _loadPrefs();
    runApp(ProviderScope(overrides: [appPrefsProvider.overrideWithValue(AppPrefs(prefs))], child: const KonektApp()));
  } catch (e, s) {
    debugPrint('[Konekt] Échec du démarrage : $e\n$s');
    runApp(StartupErrorApp(error: e, onRetry: bootstrap));
  }
}

const _stepTimeout = Duration(seconds: 8);

/// Préférences locales, avec un second essai en cas d'échec ponctuel.
Future<SharedPreferences> _loadPrefs() async {
  try {
    return await SharedPreferences.getInstance().timeout(_stepTimeout);
  } catch (_) {
    return SharedPreferences.getInstance().timeout(_stepTimeout);
  }
}
