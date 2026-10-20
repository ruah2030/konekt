import 'json.dart';

/// Mouvement du relevé émetteur. `amount` est signé (négatif = débit), en FCFA.
class CardTransaction {
  const CardTransaction({
    required this.id,
    required this.description,
    required this.kind,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory CardTransaction.fromJson(Json j) => CardTransaction(
    id: j.str('id'),
    description: j.str('description'),
    kind: j.str('kind'),
    amount: j.integer('amount'),
    balanceAfter: j.integer('balanceAfter'),
    createdAt: j.date('createdAt'),
  );

  final String id;
  final String description;

  /// `send | payout | topup | airtime | data | elec | cash | card`
  final String kind;
  final int amount;
  final int balanceAfter;
  final DateTime createdAt;

  bool get isCredit => amount > 0;
}
