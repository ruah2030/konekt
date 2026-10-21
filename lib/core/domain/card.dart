import 'json.dart';

/// Statut de carte (`CardStatus` de l'API).
enum CardStatus {
  active('Active', 'Active'),
  inactive('Inactive', 'Suspendue'),
  preActive('PreActive', 'À activer'),
  lostOrStolen('LostOrStolen', 'Bloquée'),
  deactivated('Deactivated', 'Désactivée');

  const CardStatus(this.api, this.label);
  final String api;
  final String label;

  /// Accepte le vocabulaire plateforme (`Active`…) et émetteur (`AC`, `PA`, `IA`, `LC`, `DE`).
  static CardStatus fromApi(String? v) => switch (v) {
    'Active' || 'AC' => CardStatus.active,
    'Inactive' || 'IA' => CardStatus.inactive,
    'PreActive' || 'PA' => CardStatus.preActive,
    'LostOrStolen' || 'LC' => CardStatus.lostOrStolen,
    'Deactivated' || 'DE' => CardStatus.deactivated,
    _ => CardStatus.inactive,
  };

  bool get isActive => this == CardStatus.active;

  /// Carte bloquée définitivement : plus aucune lecture ni opération possible.
  bool get isTerminal => this == CardStatus.lostOrStolen || this == CardStatus.deactivated;

  /// Message affiché quand une action est refusée à cause du statut (textes de l'API).
  String get blockedMessage => switch (this) {
    CardStatus.active => '',
    CardStatus.inactive => 'Cette carte est suspendue. Réactivez-la d’abord : tant qu’elle est suspendue, aucune autre opération n’est possible.',
    CardStatus.preActive =>
      'Cette carte n’a pas encore été activée. Rechargez-la une première fois pour commencer à l’utiliser.',
    CardStatus.lostOrStolen => 'Cette carte a été déclarée perdue ou volée. Contactez le support : vos fonds peuvent être transférés sur une nouvelle carte.',
    CardStatus.deactivated => 'Cette carte a été désactivée. Contactez le support — vos fonds ne sont pas perdus.',
  };
}

/// Carte de la session, construite depuis `GET /cards` (`data[0]`) ou, pour une carte externe,
/// depuis `GET /cards/details/:cardCustomerId`.
class CardInfo {
  const CardInfo({
    required this.cardCustomerId,
    required this.last4,
    required this.status,
    required this.product,
    required this.issuer,
    required this.holderName,
    this.brand = 'VISA',
    this.tierSlug,
    this.email,
    this.phone,
  });

  /// Élément de `GET /cards`.
  factory CardInfo.fromCardsItem(Json j) {
    final tier = j['cardTier'] is Map ? j.obj('cardTier') : null;
    final provider = tier != null && tier['provider'] is Map ? tier.obj('provider') : null;
    final holder = j['holder'] is Map ? j.obj('holder') : const <String, dynamic>{};
    final providerLabel = provider?.strOrNull('label') ?? '';
    return CardInfo(
      cardCustomerId: j.strOrNull('customerId') ?? '',
      last4: j.strOrNull('last4') ?? '',
      status: CardStatus.fromApi(j.strOrNull('status')),
      product: tier?.strOrNull('label') ?? 'Carte virtuelle',
      issuer: _issuerFrom(providerLabel),
      brand: providerLabel.toUpperCase().contains('MASTERCARD') ? 'MASTERCARD' : 'VISA',
      holderName: [holder['firstName'], holder['lastName']].whereType<String>().join(' ').toUpperCase(),
      tierSlug: j.strOrNull('cardTierSlug'),
      email: holder['email'] as String?,
      phone: holder['phone'] == null ? null : '${holder['phoneCode'] ?? ''}${holder['phone']}',
    );
  }

  /// `GET /cards/details/:id` → `card` (état réel chez l'émetteur).
  factory CardInfo.fromDetails(Json card, {required String cardCustomerId}) => CardInfo(
    cardCustomerId: cardCustomerId,
    last4: card.strOrNull('last4') ?? '',
    status: CardStatus.fromApi(card.strOrNull('status') ?? card.strOrNull('cardStatus')),
    product: 'Carte prépayée',
    issuer: 'Émetteur externe',
    holderName: [card['firstName'], card['lastName']].whereType<String>().join(' ').toUpperCase(),
    tierSlug: card.strOrNull('cardTierSlug'),
    email: card.strOrNull('emailAddress'),
    phone: card.strOrNull('mobilePhoneNumber'),
  );

  /// `UBA BJ - VISA PREPAID CARD` → `UBA Bénin`.
  static String _issuerFrom(String providerLabel) {
    final bank = providerLabel.split(' - ').first.trim();
    if (bank.isEmpty) return 'Émetteur';
    return bank.replaceAll(RegExp(r'\bBJ\b'), 'Bénin');
  }

  final String cardCustomerId;
  final String last4;
  final CardStatus status;
  final String product;
  final String issuer;
  final String brand;
  final String holderName;
  final String? tierSlug;
  final String? email;
  final String? phone;

  CardInfo copyWith({CardStatus? status}) => CardInfo(
    cardCustomerId: cardCustomerId,
    last4: last4,
    status: status ?? this.status,
    product: product,
    issuer: issuer,
    brand: brand,
    holderName: holderName,
    tierSlug: tierSlug,
    email: email,
    phone: phone,
  );
}

/// Titulaire affiché (en-tête accueil, profil) : issu de la session (`login/confirm`).
class Holder {
  const Holder({required this.firstName, required this.lastName, this.email, this.phone});

  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;

  String get fullName => [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
  String get initials =>
      [firstName, lastName].where((s) => s.isNotEmpty).map((s) => s.substring(0, 1).toUpperCase()).join();
}
