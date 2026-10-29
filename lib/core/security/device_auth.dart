import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Issue de la vérification du titulaire de l'appareil.
enum DeviceAuthResult {
  /// Empreinte, visage ou code du téléphone validé.
  authenticated,

  /// Annulée ou refusée : l'action ne doit pas être faite.
  refused,

  /// Le téléphone n'a aucun verrouillage configuré (ou pas de module) : impossible de vérifier.
  unavailable,
}

/// Déverrouillage du téléphone (empreinte, visage ou code) avant une action sensible.
///
/// L'API ne fournit aucune route pour vérifier le code secret Konekt seul, et `PATCH /cards/status`
/// n'exige ni PIN ni code (guide, point ouvert n° 6). Demander le déverrouillage de l'appareil protège
/// réellement la carte si le téléphone est volé déverrouillé.
class DeviceAuth {
  DeviceAuth([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  Future<DeviceAuthResult> confirm(String reason) async {
    try {
      if (!await _auth.isDeviceSupported()) return DeviceAuthResult.unavailable;
      final ok = await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
      return ok ? DeviceAuthResult.authenticated : DeviceAuthResult.refused;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.uiUnavailable => DeviceAuthResult.unavailable,
        _ => DeviceAuthResult.refused,
      };
    } catch (_) {
      // Module absent (tests, plateforme non prise en charge).
      return DeviceAuthResult.unavailable;
    }
  }
}

final deviceAuthProvider = Provider<DeviceAuth>((ref) => DeviceAuth());
