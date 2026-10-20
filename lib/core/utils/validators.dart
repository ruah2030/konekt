/// Validations locales (confort UX). Le serveur reste la source de vérité.
abstract final class Validators {
  static String digitsOnly(String v) => v.replaceAll(RegExp(r'\s'), '');

  /// Identifiant de carte : 6 à 20 chiffres.
  static bool isCardId(String v) => RegExp(r'^\d{6,20}$').hasMatch(digitsOnly(v));

  /// La lettre « O » saisie à la place du zéro.
  static bool containsLetterO(String v) => RegExp('[oO]').hasMatch(v);

  static bool isLast4(String v) => RegExp(r'^\d{4}$').hasMatch(v);

  /// Numéro de téléphone international ou local : 8 à 15 chiffres, `+` optionnel.
  static bool isMsisdn(String v) => RegExp(r'^\+?\d{8,15}$').hasMatch(v.replaceAll(RegExp(r'[\s-]'), ''));

  /// Compteur électrique : 6 à 20 chiffres.
  static bool isMeter(String v) => RegExp(r'^\d{6,20}$').hasMatch(digitsOnly(v));

  /// PIN trop simple : 6 chiffres identiques ou suite croissante/décroissante.
  static bool isWeakPin(String p) =>
      RegExp(r'^(\d)\1{5}$').hasMatch(p) || '0123456789'.contains(p) || '9876543210'.contains(p);

  /// Code d'invitation affiché `XXXX-XXXX` (8 caractères alphanumériques).
  static String formatInviteCode(String input) {
    var v = input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (v.length > 8) v = v.substring(0, 8);
    return v.length > 4 ? '${v.substring(0, 4)}-${v.substring(4)}' : v;
  }
}
