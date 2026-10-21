import 'package:flutter/services.dart';

/// Interdiction des captures d'écran sur les écrans sensibles (PIN, affichage de carte).
///
/// Android : `FLAG_SECURE` posé par `MainActivity` (canal `konekt/screen_security`), qui masque aussi
/// l'aperçu dans le sélecteur d'applications. iOS ne permet pas de bloquer une capture : sans effet.
/// Compteur de références : l'interdiction reste active tant qu'un écran sensible est affiché.
abstract final class ScreenSecurity {
  static const _channel = MethodChannel('konekt/screen_security');
  static int _holders = 0;

  static Future<void> set({required bool on}) async {
    _holders = on ? _holders + 1 : (_holders - 1).clamp(0, 1 << 30);
    try {
      await _channel.invokeMethod<void>(_holders > 0 ? 'enable' : 'disable');
    } catch (_) {
      // Pas d'implémentation native (tests, iOS, web) : sans conséquence.
    }
  }
}
