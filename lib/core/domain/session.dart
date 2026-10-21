import 'json.dart';

/// Session porteur = une carte (guide §1.1). Construite à partir de la réponse de
/// `POST /auth/customer/login/confirm`, conservée de façon sécurisée.
class CardSession {
  const CardSession({
    required this.cardCustomerId,
    required this.last4,
    required this.firstName,
    required this.lastName,
    required this.hasPin,
    this.isExternalCard = false,
  });

  factory CardSession.fromJson(Json j) => CardSession(
    cardCustomerId: j.str('cardCustomerId'),
    last4: j.str('last4'),
    firstName: j.strOrNull('firstName') ?? '',
    lastName: j.strOrNull('lastName') ?? '',
    hasPin: j.boolean('hasPin'),
    isExternalCard: j.boolean('isExternalCard'),
  );

  /// Réponse de `login/confirm` : `{ card: {cardCustomerId, last4Digits, status}, holder: {firstName, lastName}, hasPin, isExternalCard }`.
  factory CardSession.fromLoginConfirm(Json j) {
    final card = j.obj('card');
    final holder = j['holder'] is Map ? j.obj('holder') : const <String, dynamic>{};
    return CardSession(
      cardCustomerId: card.str('cardCustomerId'),
      last4: card.strOrNull('last4Digits') ?? '',
      firstName: holder['firstName'] as String? ?? '',
      lastName: holder['lastName'] as String? ?? '',
      hasPin: j.boolean('hasPin'),
      isExternalCard: j.boolean('isExternalCard'),
    );
  }

  /// Identifiant de carte chez l'émetteur, à renvoyer EXACTEMENT tel quel (§4.0).
  final String cardCustomerId;
  final String last4;
  final String firstName;
  final String lastName;
  final bool hasPin;

  /// Carte émise hors plateforme : masquer l'offre « acheter une carte ».
  final bool isExternalCard;

  String get fullName => [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
  String get initials =>
      [firstName, lastName].where((s) => s.isNotEmpty).map((s) => s.substring(0, 1).toUpperCase()).join();

  CardSession copyWith({bool? hasPin}) => CardSession(
    cardCustomerId: cardCustomerId,
    last4: last4,
    firstName: firstName,
    lastName: lastName,
    hasPin: hasPin ?? this.hasPin,
    isExternalCard: isExternalCard,
  );

  Json toJson() => {
    'cardCustomerId': cardCustomerId,
    'last4': last4,
    'firstName': firstName,
    'lastName': lastName,
    'hasPin': hasPin,
    'isExternalCard': isExternalCard,
  };
}
