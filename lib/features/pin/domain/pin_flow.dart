/// Contexte d'un parcours de code secret.
enum PinFlow {
  /// Premier login sans PIN (`hasPin=false`) : code reçu → nouveau → confirmation (étapes 1 à 3 sur 3).
  setup,

  /// Depuis le profil : PIN actuel → nouveau (≠ ancien) → confirmation.
  change,

  /// Code oublié : code reçu → nouveau → confirmation. Lève le verrouillage.
  reset,
}
