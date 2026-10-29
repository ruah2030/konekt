import 'dart:async';

import 'package:flutter/services.dart';

/// Protection des écrans sensibles (code secret, affichage de carte). Canal `konekt/screen_security`.
///
/// - Android (`MainActivity`) : `FLAG_SECURE` — captures et enregistrements interdits, aperçu masqué
///   dans le sélecteur d'applications.
/// - iOS (`AppDelegate.swift`) : une capture ne peut pas être interdite ; l'app est masquée dans le
///   sélecteur d'applications et pendant un enregistrement/une recopie d'écran, et chaque capture est
///   signalée ([screenshots]) pour avertir l'utilisateur.
///
/// Compteur de références : la protection reste active tant qu'un écran sensible est affiché.
abstract final class ScreenSecurity {
  static const _channel = MethodChannel('konekt/screen_security');
  static int _holders = 0;
  static bool _listening = false;
  static final _screenshots = StreamController<void>.broadcast();

  /// Captures d'écran prises pendant qu'un écran protégé est affiché (iOS).
  static Stream<void> get screenshots => _screenshots.stream;

  static Future<void> set({required bool on}) async {
    _listen();
    _holders = on ? _holders + 1 : (_holders - 1).clamp(0, 1 << 30);
    try {
      await _channel.invokeMethod<void>(_holders > 0 ? 'enable' : 'disable');
    } catch (_) {
      // Pas d'implémentation native (tests, web) : sans conséquence.
    }
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'screenshotTaken') _screenshots.add(null);
      });
    } catch (_) {
      // Pas de messagerie de plateforme (tests unitaires purs).
    }
  }
}
