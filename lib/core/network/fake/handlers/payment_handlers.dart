import 'dart:async';

import '../../../utils/money_format.dart';
import '../fake_api.dart';
import '../fake_db.dart';

/// Opérateurs Mobile Money (maquette : `OPS_MNO`).
const _operators = {'mtn': 'MTN MoMo', 'moov': 'Moov Money', 'bmo': 'BestCash Money', 'celtiis': 'Celtiis Cash'};

/// Canaux de réception du code électricité.
const _channels = {'WHATSAPP': 'WhatsApp', 'EMAIL': 'E-mail'};

/// Forfaits internet (prix imposé par l'opérateur).
const _dataPlans = [
  {'id': 'd1', 'label': '1,5 Go', 'validity': '7 jours', 'price': 1000},
  {'id': 'd2', 'label': '5 Go', 'validity': '30 jours', 'price': 3000},
  {'id': 'd3', 'label': '12 Go', 'validity': '30 jours', 'price': 6000},
  {'id': 'd4', 'label': '30 Go', 'validity': '30 jours', 'price': 12000},
];

const _titles = {
  'transfer': 'Envoyer vers une carte',
  'payout': 'Retirer vers Mobile Money',
  'topup': 'Recharger ma carte',
  'airtime': 'Crédit téléphone',
  'data': 'Forfait internet',
  'elec': 'Électricité prépayée',
  'cash': 'Retrait au guichet',
};

/// Grille de frais (maquette : `SV[...].fee`). Uniquement côté serveur.
int _fee(String service, int a) => switch (service) {
  'transfer' =>
    a <= 10000
        ? 150
        : a <= 50000
        ? 440
        : a <= 100000
        ? 800
        : (a * 0.007).round(),
  'payout' => (a * 0.022).round(),
  'topup' => (a * 0.01).round(),
  'elec' => 125,
  'cash' => (a * 0.01).round(),
  _ => 0,
};

const _blockedMessages = {
  'INACTIVE': 'Cette carte est suspendue. Réactivez-la pour payer à nouveau.',
  'PRE_ACTIVE': "Votre carte n'est pas encore activée. Rendez-vous chez votre marchand pour l'activer.",
  'LOST_OR_STOLEN': 'Carte déclarée perdue ou volée. Contactez le support : vos fonds peuvent être transférés sur une nouvelle carte.',
};

/// Délais de traitement simulés (maquette : `execute()`).
const stageDelay = Duration(milliseconds: 1100);
const approvalStageDelay = Duration(milliseconds: 1400);
const successDelay = Duration(milliseconds: 2600);
const approvalSuccessDelay = Duration(seconds: 6);

FakeResponse _invalid(String message) => FakeResponse.error(422, 'VALIDATION_FAILED', message);
FakeResponse _rejected(String message) => FakeResponse.error(422, 'REQUEST_REJECTED', message);

/// Devis, forfaits et exécution des paiements.
///
/// - `GET  /v1/services/data/plans`
/// - `POST /v1/quotes`
/// - `POST /v1/operations` (+ `Idempotency-Key`)
/// - `GET  /v1/payments/:id` : suivi d'une opération (calcule et persiste sa progression).
///
/// La progression d'une opération est calculée à partir du temps écoulé (`db.now()`) :
/// elle est appliquée à chaque appel des handlers de paiement et, hors tests (latence > 0),
/// par un `Timer` pour que l'historique reste juste même si l'utilisateur quitte l'écran.
void registerPaymentHandlers(FakeApi api) {
  final db = api.db;

  /// operationId → (heure de lancement, devis).
  final pending = <String, ({DateTime startedAt, Map<String, dynamic> quote})>{};

  void advance(String id) {
    final p = pending[id];
    final op = db.operations.where((o) => o['id'] == id).firstOrNull;
    if (p == null || op == null) return;
    final q = p.quote;
    final approval = q['requiresUserApproval'] == true;
    final elapsed = db.now().difference(p.startedAt);
    if (elapsed < (approval ? approvalSuccessDelay : successDelay)) {
      if (elapsed >= (approval ? approvalStageDelay : stageDelay)) {
        op['step'] = approval ? 'AWAITING_USER_APPROVAL' : 'PROCESSING';
      }
      return;
    }
    pending.remove(id);
    final credit = q['service'] == 'topup';
    final amount = q['amount'] as int, total = q['total'] as int;
    if (!credit && total > db.balance) {
      op
        ..['status'] = 'FAILED'
        ..['step'] = 'FAILED'
        ..['reason'] = "Solde insuffisant. Votre carte n'a pas été débitée.";
      db.addNotification('${op['title']} · échoué', '${formatFcfa(amount)} · Solde insuffisant.');
      return;
    }
    final signed = credit ? amount : -total;
    db.balance += signed;
    if (!credit) db.dailySpent += total;
    final extra = <Map<String, dynamic>>[
      if (q['service'] == 'elec')
        {
          'label': 'Code de recharge à saisir sur le compteur',
          'value': '4821 0937 5520 1184 6653',
          'note': 'Aussi envoyé par ${q['operatorLabel'] ?? 'message'}',
        },
      if (q['service'] == 'cash')
        {'label': 'Code de retrait', 'value': '738 214', 'note': 'Valable 30 minutes chez tout point marchand Konekt'},
    ];
    op
      ..['status'] = 'SUCCESS'
      ..['step'] = 'SUCCESS'
      ..['extra'] = extra;
    db.transactions.insert(0, {
      'id': db.id('tx_', 6),
      'description': op['title'],
      'kind': q['service'],
      'amount': signed,
      'balanceAfter': db.balance,
      'createdAt': db.now().toIso8601String(),
    });
    final benef = q['beneficiary'] as String?;
    db.addNotification('${op['title']} · réussi', '${formatFcfa(amount)}${benef != null ? ' · $benef' : ''}');
  }

  void advanceAll() => pending.keys.toList().forEach(advance);

  api.on('GET', '/v1/services/data/plans', (_) => const FakeResponse.ok({'items': _dataPlans}));

  api.on('POST', '/v1/quotes', (r) {
    advanceAll();
    final b = r.body;
    final service = b['service'] as String?;
    final title = _titles[service];
    if (service == null || title == null) return _rejected('Service indisponible.');
    if (db.cardStatus != 'ACTIVE') {
      return FakeResponse.error(403, 'FORBIDDEN', _blockedMessages[db.cardStatus] ?? 'Carte indisponible.');
    }
    String? str(String k) {
      final v = (b[k] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final target = str('target')?.replaceAll(RegExp(r'\s'), '');
    final msisdn = str('msisdn');
    final meter = str('meter')?.replaceAll(RegExp(r'\s'), '');
    String? operatorLabel;
    int? amount = (b['amount'] as num?)?.toInt();

    switch (service) {
      case 'transfer':
        if (target == null) return _invalid('Carte du bénéficiaire : champ obligatoire.');
        if (target == db.sessionCardId) return _rejected('La carte bénéficiaire doit être différente de la vôtre.');
      case 'payout' || 'topup':
        operatorLabel = _operators[b['operator']];
        if (operatorLabel == null) {
          return _invalid(service == 'payout' ? 'Choisissez : opérateur.' : 'Choisissez : payer avec.');
        }
      case 'data':
        final plan = _dataPlans.where((p) => p['id'] == b['planId']).firstOrNull;
        if (plan == null) return _invalid('Choisissez : forfait.');
        amount = plan['price']! as int;
        operatorLabel = '${plan['label']} · ${plan['validity']}';
      case 'elec':
        operatorLabel = _channels[b['deliveryChannel']];
        if (operatorLabel == null) return _invalid('Choisissez : recevoir le code par.');
        if (meter == null) return _invalid('Numéro du compteur : champ obligatoire.');
        if (!RegExp(r'^\d{6,20}$').hasMatch(meter)) return _rejected('Numéro de compteur : chiffres uniquement.');
        if (str('contact') == null) return _invalid('Envoyer le code à : champ obligatoire.');
    }
    if (const {'payout', 'topup', 'airtime', 'data'}.contains(service)) {
      if (msisdn == null) return _invalid('Numéro de téléphone : champ obligatoire.');
      if (!RegExp(r'^\+?\d{8,15}$').hasMatch(msisdn.replaceAll(RegExp(r'[\s-]'), ''))) {
        return _rejected('Numéro de téléphone invalide.');
      }
    }
    if (amount == null || amount < 100) return _invalid('Montant minimum : 100 FCFA.');
    if (amount > 1000000) return _invalid('Montant maximum : 1 000 000 FCFA.');
    if (db.dailySpent + amount > FakeDb.dailyLimit) {
      return FakeResponse.error(
        422,
        'DAILY_AMOUNT_LIMIT',
        'Ce montant dépasse votre plafond de 500 000 FCFA sur 24 heures.',
      );
    }
    final fee = _fee(service, amount);
    final total = amount + fee;
    if (service != 'topup' && total > db.balance) {
      return FakeResponse.error(
        422,
        'INSUFFICIENT_FUNDS',
        'Solde insuffisant : il manque ${formatFcfa(total - db.balance)} (frais compris).',
      );
    }
    final last4 = target != null && target.length >= 4 ? target.substring(target.length - 4) : target;
    final beneficiary = switch (service) {
      'transfer' => 'Afiavi Sossou · •••• $last4',
      'payout' || 'topup' => '$operatorLabel · $msisdn',
      'airtime' || 'data' => msisdn,
      'elec' => 'Compteur $meter',
      _ => null,
    };
    final check = switch (service) {
      'transfer' => {'label': 'Bénéficiaire', 'detail': 'Afiavi Sossou · carte •••• $last4', 'passed': true},
      'payout' => {'label': 'Bénéficiaire', 'detail': 'Afi Mensah · nom non vérifié', 'passed': true},
      'airtime' => {'label': 'Opérateur', 'detail': 'MTN Bénin · de 100 à 50 000 FCFA', 'passed': true},
      'data' => {'label': 'Opérateur', 'detail': 'MTN Bénin', 'passed': true},
      'elec' => {
        'label': 'Compteur',
        'detail': 'HOUNGBÉDJI AWA · ≈ ${(amount / 104).toStringAsFixed(1).replaceAll('.', ',')} kWh',
        'passed': true,
      },
      _ => null,
    };
    final quote = <String, dynamic>{
      'quoteId': db.id('qt_', 10),
      'service': service,
      'title': title,
      'amount': amount,
      'fee': fee,
      'total': total,
      'currency': 'XOF',
      'expiresAt': db.now().add(const Duration(minutes: 10)).toIso8601String(),
      'beneficiary': beneficiary,
      'operatorLabel': operatorLabel,
      'requiresUserApproval': service == 'topup',
      'checks': [?check],
      'warnings': [
        if (service == 'payout') 'Vérifiez le numéro avant de confirmer : un versement abouti ne peut pas être repris.',
      ],
    };
    db.quotes[quote['quoteId'] as String] = quote;
    return FakeResponse.ok(quote);
  });

  api.on('POST', '/v1/operations', (r) {
    advanceAll();
    final quoteId = r.body['quoteId'] as String?;
    final key = r.options.headers['Idempotency-Key'] as String? ?? quoteId;
    final existing = key == null ? null : db.idempotency[key];
    if (existing != null) {
      final op = db.operations.where((o) => o['id'] == existing).firstOrNull;
      if (op != null) return FakeResponse.ok({'operation': op});
    }
    final quote = quoteId == null ? null : db.quotes[quoteId];
    if (quote == null) return FakeResponse.error(404, 'NOT_FOUND', 'Devis introuvable. Refaites le devis.');
    if (db.cardStatus != 'ACTIVE') {
      return FakeResponse.error(403, 'FORBIDDEN', _blockedMessages[db.cardStatus] ?? 'Carte indisponible.');
    }
    if (db.pin == null) return FakeResponse.error(403, 'FORBIDDEN', "Créez d'abord votre code secret dans Profil.");
    final now = db.now();
    final lockedUntil = db.pinLockedUntil;
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      final minutes = (lockedUntil.difference(now).inSeconds / 60).ceil();
      return FakeResponse.error(
        403,
        'FORBIDDEN',
        'Réessayez dans $minutes minute(s), ou réinitialisez votre code secret.',
        details: {'lockedUntil': lockedUntil.toIso8601String()},
      );
    }
    if (now.isAfter(DateTime.parse(quote['expiresAt'] as String))) return _rejected('Prix expiré. Refaites le devis.');
    if (r.body['pin'] != db.pin) {
      final tries = db.pinTries - 1;
      if (tries <= 0) {
        db
          ..pinTries = 5
          ..pinLockedUntil = now.add(const Duration(minutes: 15));
        return FakeResponse.error(
          403,
          'FORBIDDEN',
          'Trop de codes erronés. Réessayez dans 15 minutes, ou réinitialisez votre code secret.',
          details: {'lockedUntil': db.pinLockedUntil!.toIso8601String(), 'triesLeft': 0},
        );
      }
      db.pinTries = tries;
      return FakeResponse.error(
        403,
        'FORBIDDEN',
        'Code secret incorrect. $tries essai(s) avant verrouillage.',
        details: {'triesLeft': tries},
      );
    }
    db
      ..pinTries = 5
      ..pinLockedUntil = null;
    final op = <String, dynamic>{
      'id': db.id('op_'),
      'quoteId': quoteId,
      'service': quote['service'],
      'title': quote['title'],
      'status': 'PROCESSING',
      'step': 'AUTHORIZED',
      'amount': quote['amount'],
      'fee': quote['fee'],
      'total': quote['total'],
      'direction': quote['service'] == 'topup' ? 'CREDIT' : 'DEBIT',
      'beneficiary': quote['beneficiary'],
      'operatorLabel': quote['operatorLabel'],
      'extra': <Map<String, dynamic>>[],
      'createdAt': now.toIso8601String(),
    };
    db.operations.insert(0, op);
    db.idempotency[key!] = op['id'] as String;
    pending[op['id'] as String] = (startedAt: now, quote: quote);
    if (api.latency > Duration.zero) {
      final approval = quote['requiresUserApproval'] == true;
      for (final d in [approval ? approvalStageDelay : stageDelay, approval ? approvalSuccessDelay : successDelay]) {
        Timer(d + const Duration(milliseconds: 50), () => advance(op['id'] as String));
      }
    }
    return FakeResponse.ok({'operation': op});
  });

  api.on('GET', '/v1/payments/:id', (r) {
    final id = r.pathParams['id']!;
    advance(id);
    final op = db.operations.where((o) => o['id'] == id).firstOrNull;
    return op == null ? FakeResponse.error(404, 'NOT_FOUND', 'Opération introuvable.') : FakeResponse.ok(op);
  });
}
