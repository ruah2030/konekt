import 'json.dart';
import 'service_type.dart';

/// `OperationStatus` de l'API (guide Partie 6 §7.1).
enum OperationStatus {
  initialized('INITIALIZED'),
  pending('PENDING'),
  pendingApproval('PENDING_APPROVAL'),
  processing('PROCESSING'),
  success('SUCCESS'),
  failed('FAILED'),
  cancelled('CANCELLED'),
  reversed('REVERSED'),
  refunded('REFUNDED'),
  expired('EXPIRED');

  const OperationStatus(this.api);
  final String api;

  static OperationStatus fromApi(String? v) =>
      values.firstWhere((s) => s.api == v, orElse: () => OperationStatus.processing);

  /// `INITIALIZED`, `PENDING`, `PENDING_APPROVAL`, `PROCESSING` : ce n'est pas fini, ne rien relancer.
  bool get isFinal => !const {initialized, pending, pendingApproval, processing}.contains(this);

  bool get isSuccess => this == success;

  /// Échec du point de vue du porteur (`FAILED`, `CANCELLED`, `EXPIRED`).
  bool get isFailure => const {failed, cancelled, expired}.contains(this);

  String get label => switch (this) {
    success => 'Réussi',
    failed => 'Échoué',
    cancelled => 'Annulé',
    expired => 'Expiré',
    reversed => 'Contre-passé',
    refunded => 'Remboursé',
    _ => 'En cours',
  };
}

/// Carte impliquée dans une opération (`cards[]`).
class OperationCard {
  const OperationCard({required this.role, this.cardCustomerId, this.last4, this.holderName});
  factory OperationCard.fromJson(Json j) => OperationCard(
    role: j.strOrNull('role') ?? 'MAIN',
    cardCustomerId: j.strOrNull('cardCustomerId'),
    last4: j.strOrNull('cardLast4') ?? j.strOrNull('last4'),
    holderName: j.strOrNull('holderName'),
  );

  /// `MAIN` | `SOURCE` | `TARGET`.
  final String role;
  final String? cardCustomerId;
  final String? last4;
  final String? holderName;
}

/// Payeur ou bénéficiaire externe (`parties[]`), ex. portefeuille Mobile Money.
class OperationParty {
  const OperationParty({required this.role, this.name, this.identifier, this.channelLabel, this.verified = false});
  factory OperationParty.fromJson(Json j) => OperationParty(
    role: j.strOrNull('role') ?? 'BENEFICIARY',
    name: j.strOrNull('name'),
    identifier: j.strOrNull('identifier'),
    channelLabel: j.strOrNull('channelLabel'),
    verified: j.boolean('verified'),
  );

  /// `PAYER` | `BENEFICIARY`.
  final String role;
  final String? name;
  final String? identifier;
  final String? channelLabel;
  final bool verified;

  String get display => [channelLabel, name, identifier].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

/// Information complémentaire du reçu (code de recharge électricité, code de retrait…),
/// fournie par la confirmation du paiement.
class ReceiptExtra {
  const ReceiptExtra({required this.label, required this.value, this.note});
  final String label;
  final String value;
  final String? note;
}

/// Opération plateforme (`GET /operations`, `GET /operations/:id`, `GET /cards/operations/:id`).
class Operation {
  const Operation({
    required this.id,
    required this.status,
    required this.title,
    required this.amount,
    required this.fee,
    required this.amountDebited,
    required this.amountCredited,
    required this.createdAt,
    this.type,
    this.reference,
    this.serviceSlug,
    this.cards = const [],
    this.parties = const [],
    this.failureReason,
    this.cancellationReason,
    this.sessionCardCustomerId,
    this.awaiting,
  });

  /// Élément de `GET /operations` ou `data` de `GET /operations/:id`.
  /// [sessionCardCustomerId] sert à savoir si la carte de session est débitée ou créditée.
  factory Operation.fromJson(Json j, {String? sessionCardCustomerId}) {
    final service = j['service'] is Map ? j.obj('service') : null;
    final amount = (j['amount'] as num?) ?? 0;
    final fee = (j['fee'] as num?) ?? 0;
    return Operation(
      id: j.strOrNull('id') ?? j.str('operationId'),
      type: j.strOrNull('type'),
      status: OperationStatus.fromApi(j.strOrNull('status')),
      reference: j.strOrNull('reference'),
      title: service?.strOrNull('label') ?? 'Opération',
      serviceSlug: service?.strOrNull('slug'),
      amount: amount,
      fee: fee,
      amountDebited: (j['amountDebited'] as num?) ?? amount + fee,
      amountCredited: (j['amountCredited'] as num?) ?? amount,
      cards: j.list('cards').map(OperationCard.fromJson).toList(),
      parties: j.list('parties').map(OperationParty.fromJson).toList(),
      failureReason: j.strOrNull('failureReason') ?? j.strOrNull('reason'),
      cancellationReason: j.strOrNull('cancellationReason'),
      createdAt: j.date('createdAt'),
      sessionCardCustomerId: sessionCardCustomerId,
      awaiting: j.strOrNull('awaiting'),
    );
  }

  final String id;
  final String? type;
  final OperationStatus status;
  final String? reference;
  final String title;
  final String? serviceSlug;
  final num amount;
  final num fee;

  /// Ce qui a quitté la source (montant + frais).
  final num amountDebited;

  /// Ce qui est parvenu au destinataire.
  final num amountCredited;
  final List<OperationCard> cards;
  final List<OperationParty> parties;
  final String? failureReason;
  final String? cancellationReason;
  final DateTime createdAt;
  final String? sessionCardCustomerId;

  /// `PAYER_APPROVAL` | `CONFIRMATION_CODE` | `PROVIDER_SETTLEMENT` (si `PENDING`).
  final String? awaiting;

  ServiceType? get service => ServiceType.fromApi(serviceSlug);

  bool get isFinal => status.isFinal;

  /// La carte de session reçoit l'argent (recharge, transfert reçu).
  bool get isCredit {
    if (service == ServiceType.topup) return true;
    final mine = sessionCardCustomerId == null
        ? null
        : cards.where((c) => c.cardCustomerId == sessionCardCustomerId).firstOrNull;
    return mine?.role == 'TARGET';
  }

  /// Montant affiché : crédité pour une recharge, total débité sinon.
  num get signedDisplayAmount => isCredit ? amountCredited : -amountDebited;

  /// Motif d'échec ou d'annulation.
  String? get reason => failureReason ?? cancellationReason;

  /// Contrepartie lisible : carte destinataire (« Afiavi Sossou · •••• 9034 ») ou portefeuille.
  String? get counterparty {
    final target = cards.where((c) => c.role == 'TARGET' && c.cardCustomerId != sessionCardCustomerId).firstOrNull;
    if (target != null) {
      return [target.holderName, if (target.last4 != null) '•••• ${target.last4}'].whereType<String>().join(' · ');
    }
    final party = parties.where((p) => p.role == (isCredit ? 'PAYER' : 'BENEFICIARY')).firstOrNull;
    return party?.display;
  }
}
