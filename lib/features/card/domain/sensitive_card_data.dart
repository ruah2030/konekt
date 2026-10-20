import '../../../core/domain/json.dart';

/// Données sensibles de la carte (PAN, expiration, CVV), valables jusqu'à [expiresAt].
///
/// Ne JAMAIS les stocker (prefs, cache disque) ni les journaliser : elles ne vivent
/// qu'en mémoire, le temps de l'affichage sécurisé.
class SensitiveCardData {
  const SensitiveCardData({required this.pan, required this.expiry, required this.cvv, required this.expiresAt});

  factory SensitiveCardData.fromJson(Json j) =>
      SensitiveCardData(pan: j.str('pan'), expiry: j.str('expiry'), cvv: j.str('cvv'), expiresAt: j.date('expiresAt'));

  /// Durée de validité d'un affichage.
  static const validity = Duration(seconds: 60);

  final String pan;
  final String expiry;
  final String cvv;
  final DateTime expiresAt;

  /// Masqué pour éviter toute fuite accidentelle dans les logs.
  @override
  String toString() => 'SensitiveCardData(••••, expiresAt: $expiresAt)';
}
