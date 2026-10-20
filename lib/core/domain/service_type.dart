/// Services de paiement proposés dans l'app. `id` = valeur `service` de l'API.
enum ServiceType {
  transfer('transfer', 'Envoyer vers une carte'),
  payout('payout', 'Retirer vers Mobile Money'),
  topup('topup', 'Recharger ma carte'),
  airtime('airtime', 'Crédit téléphone'),
  data('data', 'Forfait internet'),
  elec('elec', 'Électricité prépayée'),
  tv('tv', 'Abonnement TV'),
  cash('cash', 'Retrait au guichet');

  const ServiceType(this.id, this.title);
  final String id;
  final String title;

  static ServiceType? tryParse(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Débit (−1) ou crédit (+1) de la carte.
  int get direction => this == ServiceType.topup ? 1 : -1;
}
