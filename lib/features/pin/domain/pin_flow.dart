/// Contexte d'un parcours de code secret.
enum PinFlow {
  /// Premier login sans PIN : vérification → nouveau → confirmation (Étape 1 à 3 sur 3).
  setup,

  /// Depuis le profil : PIN actuel → nouveau (≠ ancien) → confirmation.
  change,

  /// Code oublié (profil ou paiement) : vérification → nouveau → confirmation. Lève le verrouillage.
  reset,
}
