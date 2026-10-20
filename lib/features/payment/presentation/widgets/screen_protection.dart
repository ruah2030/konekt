import 'package:screen_protector/screen_protector.dart';

/// Active/désactive l'interdiction de capture d'écran. Sans effet si le plugin est absent (tests).
Future<void> setScreenProtection({required bool on}) async {
  try {
    if (on) {
      await ScreenProtector.preventScreenshotOn();
    } else {
      await ScreenProtector.preventScreenshotOff();
    }
  } catch (_) {
    // Plugin indisponible (tests, plateforme non supportée).
  }
}
