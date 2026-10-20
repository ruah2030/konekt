import '../../../core/domain/json.dart';
import '../../../core/domain/service_type.dart';

/// Contrôle effectué par le serveur lors du devis (nom du bénéficiaire, opérateur, compteur).
class QuoteCheck {
  const QuoteCheck({required this.label, required this.detail, required this.passed});
  factory QuoteCheck.fromJson(Json j) =>
      QuoteCheck(label: j.str('label'), detail: j.str('detail'), passed: j.boolean('passed'));
  final String label;
  final String detail;
  final bool passed;
}

/// Devis (`POST /v1/quotes`) : prix exact garanti jusqu'à [expiresAt].
class Quote {
  const Quote({
    required this.quoteId,
    required this.service,
    required this.amount,
    required this.fee,
    required this.total,
    required this.expiresAt,
    this.currency = 'XOF',
    this.beneficiary,
    this.operatorLabel,
    this.requiresUserApproval = false,
    this.checks = const [],
    this.warnings = const [],
  });

  factory Quote.fromJson(Json j) => Quote(
    quoteId: j.str('quoteId'),
    service: ServiceType.tryParse(j.str('service'))!,
    amount: j.integer('amount'),
    fee: j.integer('fee'),
    total: j.integer('total'),
    currency: j.strOrNull('currency') ?? 'XOF',
    expiresAt: j.date('expiresAt'),
    beneficiary: j.strOrNull('beneficiary'),
    operatorLabel: j.strOrNull('operatorLabel'),
    requiresUserApproval: j.boolean('requiresUserApproval'),
    checks: j.list('checks').map(QuoteCheck.fromJson).toList(),
    warnings: j.strings('warnings'),
  );

  final String quoteId;
  final ServiceType service;
  final int amount;
  final int fee;
  final int total;
  final String currency;
  final DateTime expiresAt;
  final String? beneficiary;
  final String? operatorLabel;
  final bool requiresUserApproval;
  final List<QuoteCheck> checks;
  final List<String> warnings;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);
}

/// Forfait internet (`GET /v1/services/data/plans`).
class DataPlan {
  const DataPlan({required this.id, required this.label, required this.validity, required this.price});
  factory DataPlan.fromJson(Json j) =>
      DataPlan(id: j.str('id'), label: j.str('label'), validity: j.str('validity'), price: j.integer('price'));
  final String id;
  final String label;
  final String validity;
  final int price;
}
