import '../../../../core/security/screen_security.dart';

/// Active/désactive l'interdiction de capture d'écran.
Future<void> setScreenProtection({required bool on}) => ScreenSecurity.set(on: on);
