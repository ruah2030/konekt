import 'json.dart';

enum CardStatus {
  active('ACTIVE', 'Active'),
  inactive('INACTIVE', 'Suspendue'),
  preActive('PRE_ACTIVE', 'À activer'),
  lostOrStolen('LOST_OR_STOLEN', 'Bloquée');

  const CardStatus(this.api, this.label);
  final String api;
  final String label;

  static CardStatus fromApi(String v) => values.firstWhere((s) => s.api == v, orElse: () => CardStatus.inactive);

  bool get isActive => this == CardStatus.active;

  /// Message affiché quand une action est refusée à cause du statut.
  String get blockedMessage => switch (this) {
    CardStatus.active => '',
    CardStatus.inactive => 'Cette carte est suspendue. Réactivez-la pour payer à nouveau.',
    CardStatus.preActive => "Votre carte n'est pas encore activée. Rendez-vous chez votre marchand pour l'activer.",
    CardStatus.lostOrStolen => 'Carte déclarée perdue ou volée. Contactez le support : vos fonds peuvent être transférés sur une nouvelle carte.',
  };
}

class CardInfo {
  const CardInfo({
    required this.id,
    required this.last4,
    required this.status,
    required this.brand,
    required this.product,
    required this.issuer,
    required this.holderName,
  });

  factory CardInfo.fromJson(Json j) => CardInfo(
    id: j.str('id'),
    last4: j.str('last4'),
    status: CardStatus.fromApi(j.str('status')),
    brand: j.str('brand'),
    product: j.str('product'),
    issuer: j.str('issuer'),
    holderName: j.str('holderName'),
  );

  final String id;
  final String last4;
  final CardStatus status;
  final String brand;
  final String product;
  final String issuer;
  final String holderName;

  CardInfo copyWith({CardStatus? status}) => CardInfo(
    id: id,
    last4: last4,
    status: status ?? this.status,
    brand: brand,
    product: product,
    issuer: issuer,
    holderName: holderName,
  );
}

class Holder {
  const Holder({
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.initials,
    required this.maskedPhone,
    this.email,
  });

  factory Holder.fromJson(Json j) => Holder(
    firstName: j.str('firstName'),
    lastName: j.str('lastName'),
    fullName: j.str('fullName'),
    initials: j.str('initials'),
    maskedPhone: j.str('maskedPhone'),
    email: j.strOrNull('email'),
  );

  final String firstName;
  final String lastName;
  final String fullName;
  final String initials;
  final String maskedPhone;
  final String? email;
}
