/// Validation locale du PIN avant l'envoi (guide §7.4) : le serveur applique les mêmes règles
/// (400 `PIN_TOO_WEAK`), la vérification locale donne un retour immédiat.
abstract final class PinRules {
  static const formatMessage = 'Six chiffres attendus.';
  static const repeatedMessage = 'Évitez un code composé six fois du même chiffre.';
  static const sequenceMessage = 'Évitez une suite de chiffres consécutifs.';

  /// Message du problème, ou `null` si le PIN est acceptable.
  static String? problem(String pin) {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return formatMessage;
    if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) return repeatedMessage;
    if ('0123456789'.contains(pin) || '9876543210'.contains(pin)) return sequenceMessage;
    return null;
  }
}
