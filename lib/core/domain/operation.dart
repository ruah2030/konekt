import 'json.dart';
import 'service_type.dart';

enum OperationStatus {
  processing('PROCESSING'),
  success('SUCCESS'),
  failed('FAILED');

  const OperationStatus(this.api);
  final String api;
  static OperationStatus fromApi(String v) =>
      values.firstWhere((s) => s.api == v, orElse: () => OperationStatus.processing);
}

/// Étape fine d'une opération en cours (pour le stepper de traitement).
enum OperationStep {
  quoted('QUOTED'),
  authorized('AUTHORIZED'),
  awaitingUserApproval('AWAITING_USER_APPROVAL'),
  processing('PROCESSING'),
  success('SUCCESS'),
  failed('FAILED');

  const OperationStep(this.api);
  final String api;
  static OperationStep fromApi(String? v) =>
      values.firstWhere((s) => s.api == v, orElse: () => OperationStep.processing);
}

/// Information complémentaire du reçu (code de recharge électricité, code de retrait…).
class ReceiptExtra {
  const ReceiptExtra({required this.label, required this.value, this.note});
  factory ReceiptExtra.fromJson(Json j) =>
      ReceiptExtra(label: j.str('label'), value: j.str('value'), note: j.strOrNull('note'));
  final String label;
  final String value;
  final String? note;
}

/// Opération lancée depuis Konekt (paiement, envoi, recharge…).
class Operation {
  const Operation({
    required this.id,
    required this.service,
    required this.title,
    required this.status,
    required this.step,
    required this.amount,
    required this.fee,
    required this.total,
    required this.isCredit,
    required this.createdAt,
    this.beneficiary,
    this.reason,
    this.extra = const [],
  });

  factory Operation.fromJson(Json j) => Operation(
    id: j.str('id'),
    service: ServiceType.tryParse(j.strOrNull('service')),
    title: j.str('title'),
    status: OperationStatus.fromApi(j.str('status')),
    step: OperationStep.fromApi(j.strOrNull('step')),
    amount: j.integer('amount'),
    fee: j.integer('fee'),
    total: j.integer('total'),
    isCredit: j.strOrNull('direction') == 'CREDIT',
    createdAt: j.date('createdAt'),
    beneficiary: j.strOrNull('beneficiary'),
    reason: j.strOrNull('reason'),
    extra: j.list('extra').map(ReceiptExtra.fromJson).toList(),
  );

  final String id;
  final ServiceType? service;
  final String title;
  final OperationStatus status;
  final OperationStep step;
  final int amount;
  final int fee;
  final int total;
  final bool isCredit;
  final DateTime createdAt;
  final String? beneficiary;
  final String? reason;
  final List<ReceiptExtra> extra;

  bool get isFinal => status != OperationStatus.processing;

  /// Montant affiché : crédité pour une recharge, total débité sinon.
  int get signedDisplayAmount => isCredit ? amount : -total;
}
