/// Services de paiement proposés dans l'app.
///
/// [apiKey] = clé `service` du catalogue (`POST /catalog/quote`) ou slug d'un service carte
/// (`kind: CARD_SERVICE` dans `GET /catalog/services`).
enum ServiceType {
  transfer('transfer', 'Envoyer vers une carte', 'merchant:card:transfer'),
  payout('payout', 'Retirer vers Mobile Money', 'merchant:card:card-to-wallet'),
  topup('topup', 'Recharger ma carte', 'wallet-to-card'),
  airtime('airtime', 'Crédit téléphone', 'mobile-topup'),
  data('data', 'Forfait internet', 'mobile-data'),
  elec('elec', 'Électricité prépayée', 'electricity-prepaid'),
  elecBill('elecBill', 'Facture d’électricité', 'electricity-postpaid'),
  tv('tv', 'Abonnement TV', 'tv-subscription'),
  cash('cash', 'Retrait au guichet', 'cash-withdrawal');

  const ServiceType(this.id, this.title, this.apiKey);

  /// Identifiant interne de l'app (routes `/pay/:id`, promotions).
  final String id;
  final String title;
  final String apiKey;

  static ServiceType? tryParse(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Retrouve le service à partir d'une clé catalogue ou d'un slug de service API
  /// (`merchant:addon:sell-mno-airtime:from-card` → [airtime]).
  static ServiceType? fromApi(String? keyOrSlug) {
    if (keyOrSlug == null) return null;
    for (final s in values) {
      if (s.apiKey == keyOrSlug) return s;
    }
    final k = keyOrSlug.toLowerCase();
    if (k.contains('card:transfer')) return transfer;
    if (k.contains('card-to-wallet') || k.contains('payout')) return payout;
    if (k.contains('wallet-to-card')) return topup;
    if (k.contains('airtime') || k.contains('mobile-topup')) return airtime;
    if (k.contains('mno-data') || k.contains('mobile-data')) return data;
    if (k.contains('electricity-postpaid')) return elecBill;
    if (k.contains('electricity')) return elec;
    if (k.contains('tv')) return tv;
    if (k.contains('atm') || k.contains('cash')) return cash;
    return null;
  }

  /// Débit (−1) ou crédit (+1) de la carte.
  int get direction => this == ServiceType.topup ? 1 : -1;

  /// Service de la famille `/cards/*` (initiate → execute) plutôt que du catalogue.
  bool get isCardService => this == ServiceType.transfer || this == ServiceType.payout;
}
