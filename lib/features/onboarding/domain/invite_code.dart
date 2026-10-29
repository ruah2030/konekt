/// Règles du code d'invitation marchand (`merchantReferralCode`, guide §2.4 : ≤ 40 caractères ;
/// un code inconnu ne bloque pas la connexion). Partagées par la saisie manuelle et les liens d'invitation.
abstract final class InviteCode {
  static const minLength = 4;
  static const maxLength = 40;
  static const formatMessage = 'Code invalide : 4 à 40 lettres ou chiffres.';

  /// Saisie : majuscules, lettres, chiffres, `-` et `_`, tronquée à [maxLength].
  static String normalize(String input) {
    final v = input.toUpperCase().replaceAll(RegExp('[^A-Z0-9_-]'), '');
    return v.length > maxLength ? v.substring(0, maxLength) : v;
  }

  static bool isValid(String code) => RegExp(r'^[A-Z0-9][A-Z0-9_-]{3,39}$').hasMatch(code);
}
