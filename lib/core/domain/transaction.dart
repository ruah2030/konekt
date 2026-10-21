import 'json.dart';

/// Mouvement du relevé émetteur (`GET /cards/transactions/:cardCustomerId`).
///
/// L'émetteur ne fournit pas de sens (débit/crédit) : il est déduit de l'évolution de
/// `runningBalance` entre deux mouvements consécutifs, sinon du libellé (à confirmer avec l'API).
class CardTransaction {
  const CardTransaction({
    required this.id,
    required this.description,
    required this.amount,
    required this.fee,
    required this.balanceAfter,
    required this.createdAt,
    this.reference,
  });

  /// Convertit une page du relevé (du plus récent au plus ancien). Les champs peuvent manquer.
  static List<CardTransaction> listFromIssuer(List<Json> rows) => [
    for (var i = 0; i < rows.length; i++) _fromIssuer(rows[i], i + 1 < rows.length ? rows[i + 1] : null),
  ];

  static CardTransaction _fromIssuer(Json j, Json? older) {
    final base = (j['baseAmount'] as num?) ?? 0;
    final total = (j['totalAmount'] as num?) ?? base;
    final fee = (j['fee'] as num?) ?? 0;
    final running = j['runningBalance'] as num?;
    final desc = (j['transactionDesc'] as String?)?.trim() ?? 'Mouvement';
    bool? credit;
    final olderRunning = older?['runningBalance'] as num?;
    if (running != null && olderRunning != null && running != olderRunning) credit = running > olderRunning;
    credit ??= _creditKeywords.hasMatch(desc.toLowerCase());
    return CardTransaction(
      id: '${j['transactionId'] ?? j['referenceInformation'] ?? desc.hashCode}',
      description: desc,
      amount: credit ? base : -total,
      fee: fee,
      balanceAfter: running,
      createdAt: parseIssuerDate(j.strOrNull('transactionDate'), j.strOrNull('transactionTimeHH24')),
      reference: j.strOrNull('referenceInformation'),
    );
  }

  static final _creditKeywords = RegExp(r'recharg|entrant|re[çc]u|rembours|d[ée]p[ôo]t');
  static const _months = {
    'JAN': 1,
    'FEB': 2,
    'MAR': 3,
    'APR': 4,
    'MAY': 5,
    'JUN': 6,
    'JUL': 7,
    'AUG': 8,
    'SEP': 9,
    'OCT': 10,
    'NOV': 11,
    'DEC': 12,
  };

  /// `17-AUG-2026` + `14:14:22` (heure locale de l'émetteur) → DateTime.
  static DateTime parseIssuerDate(String? date, String? time) {
    final p = (date ?? '').toUpperCase().split('-');
    if (p.length != 3) return DateTime.fromMillisecondsSinceEpoch(0);
    final t = (time ?? '00:00:00').split(':').map((e) => int.tryParse(e) ?? 0).toList();
    return DateTime(
      int.tryParse(p[2]) ?? 1970,
      _months[p[1]] ?? 1,
      int.tryParse(p[0]) ?? 1,
      t.isNotEmpty ? t[0] : 0,
      t.length > 1 ? t[1] : 0,
      t.length > 2 ? t[2] : 0,
    );
  }

  final String id;
  final String description;

  /// Montant signé en XOF (négatif = débit, frais compris).
  final num amount;
  final num fee;
  final num? balanceAfter;
  final DateTime createdAt;
  final String? reference;

  bool get isCredit => amount > 0;

  /// Catégorie d'icône déduite du libellé.
  String get kind {
    final d = description.toLowerCase();
    if (isCredit) return 'topup';
    if (d.contains('transfert')) return 'send';
    if (d.contains('guichet')) return 'cash';
    if (d.contains('retrait')) return 'payout';
    if (d.contains('électricité') || d.contains('electricite') || d.contains('sbee')) return 'elec';
    if (d.contains('forfait') || d.contains('internet')) return 'data';
    if (d.contains('crédit') || d.contains('credit')) return 'airtime';
    return 'card';
  }
}
