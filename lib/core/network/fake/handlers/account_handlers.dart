import '../fake_api.dart';
import '../fake_db.dart';

/// 403 si [cardCustomerId] n'est pas la carte de session (guide Partie 4 §4.0).
FakeResponse? assertSessionCard(FakeDb db, String? cardCustomerId) {
  final id = (cardCustomerId ?? '').replaceAll(RegExp(r'\s'), '');
  if (RegExp('[oO]').hasMatch(id) || !RegExp(r'^\d{6,20}$').hasMatch(id)) {
    return FakeResponse.error(
      400,
      'REQUEST_REJECTED',
      'Identifiant de carte invalide : chiffres uniquement (vérifiez qu’aucune lettre « O » n’a été saisie à la place du zéro).',
    );
  }
  if (id != db.sessionCardId) {
    return FakeResponse.error(
      403,
      'FORBIDDEN',
      'Vous ne pouvez agir que sur la carte avec laquelle vous vous êtes connecté. Reconnectez-vous avec l’autre carte pour l’utiliser.',
    );
  }
  return null;
}

/// Messages de refus d'état de la carte (lecture du solde, du relevé, débits).
FakeResponse? cardStateRefusal(FakeDb db, {bool allowInactive = false}) => switch (db.cardStatus) {
  'Inactive' when !allowInactive => FakeResponse.error(
    400,
    'REQUEST_REJECTED',
    'Cette carte est suspendue. Réactivez-la d’abord : tant qu’elle est suspendue, aucune autre opération n’est possible.',
  ),
  'LostOrStolen' => FakeResponse.error(
    400,
    'REQUEST_REJECTED',
    'Cette carte a été déclarée perdue ou volée. Contactez le support : vos fonds peuvent être transférés sur une nouvelle carte.',
  ),
  'Deactivated' => FakeResponse.error(
    400,
    'REQUEST_REJECTED',
    'Cette carte a été désactivée. Contactez le support — vos fonds ne sont pas perdus.',
  ),
  _ => null,
};

/// Pagination `page`/`limit` au format de l'API.
Map<String, dynamic> pageOf(List<Map<String, dynamic>> all, Map<String, dynamic> query, {int maxLimit = 100}) {
  final limit = int.tryParse('${query['limit'] ?? 20}') ?? 20;
  final page = int.tryParse('${query['page'] ?? 1}') ?? 1;
  final start = ((page - 1) * limit).clamp(0, all.length);
  final end = (start + limit).clamp(0, all.length);
  final totalPages = all.isEmpty ? 0 : (all.length / limit).ceil();
  return {
    'data': all.sublist(start, end),
    'pagination': {
      'total': all.length,
      'page': page,
      'limit': limit,
      'totalPages': totalPages,
      'hasNextPage': page < totalPages,
      'hasPreviousPage': page > 1,
    },
  };
}

FakeResponse? _limitError(Map<String, dynamic> query, int max) {
  final limit = int.tryParse('${query['limit'] ?? 20}') ?? 20;
  if (limit < 1 || limit > max) {
    return FakeResponse.validation({
      'limit': ['limit must not be greater than $max'],
    });
  }
  return null;
}

/// `OperationStatus` / `OperationType` (guide Partie 6 §7.1, §7.2) : filtres de `GET /operations`.
const _operationStatuses = [
  'INITIALIZED',
  'PENDING',
  'PENDING_APPROVAL',
  'PROCESSING',
  'SUCCESS',
  'FAILED',
  'CANCELLED',
  'REVERSED',
  'REFUNDED',
  'EXPIRED',
];
const _operationTypes = [
  'CARD_OPERATION',
  'WALLET_OPERATION',
  'ADDON_SALE',
  'CASH_WITHDRAWAL',
  'REFUND',
  'BANK_TRANSFER',
  'CARD_STOCK_OPERATION',
  'COMMISSION_PAYOUT',
];

/// Filtre de date de `GET /operations` (`@IsDateString`) : `AAAA-MM-JJ` (début du jour, jour réel exigé)
/// ou date-heure ISO 8601. Null si invalide.
DateTime? _parseOperationDay(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s) ? DateTime.tryParse(s)?.toLocal() : null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final day = DateTime(y, mo, d);
  return day.year == y && day.month == mo && day.day == d ? day : null;
}

/// Lectures partagées : carte, solde, relevé, opérations, notifications, statut, catalogue.
void registerAccountHandlers(FakeApi api) {
  final db = api.db;

  // ---- Cartes (Partie 4 §1 à §4) ----
  api.on('GET', '/cards', (_) {
    final items = db.isExternalCard ? <Map<String, dynamic>>[] : [db.cardJson()];
    return FakeResponse.ok({'success': true, ...pageOf(items, const {}), 'stats': null});
  });

  api.on('GET', '/cards/details/:id', (r) {
    final refused = assertSessionCard(db, r.pathParams['id']);
    if (refused != null) return refused;
    if (db.cardStatus == 'LostOrStolen' || db.cardStatus == 'Deactivated') return cardStateRefusal(db)!;
    return FakeResponse.ok({
      'success': true,
      'card': {
        'firstName': db.holder['firstName'],
        'lastName': db.holder['lastName'],
        'mobilePhoneNumber': '229${db.holder['phone']}',
        'emailAddress': db.holder['email'],
        'cardStatus': db.issuerStatus,
        'status': db.cardStatus,
        'last4': db.last4,
        'cardTierSlug': 'virtual:uba-bj:visa-prepaid-card:6-month',
      },
    });
  });

  api.on('GET', '/cards/balance/:id', (r) {
    final refused = assertSessionCard(db, r.pathParams['id']) ?? cardStateRefusal(db);
    if (refused != null) return refused;
    if (db.cardStatus == 'PreActive') {
      // Devise en minuscules dans ce cas précis (guide §2) : l'app normalise.
      return const FakeResponse.ok({'success': true, 'balance': 0, 'currencyIsoCode': 'xof'});
    }
    return FakeResponse.ok({'success': true, 'balance': db.balance, 'currencyIsoCode': 'XOF'});
  });

  api.on('GET', '/cards/transactions/:id', (r) {
    final refused = assertSessionCard(db, r.pathParams['id']) ?? cardStateRefusal(db);
    if (refused != null) return refused;
    if (db.cardStatus == 'PreActive') return const FakeResponse.ok({'success': true, 'transactions': <Object>[]});
    final end = _parseDate(r.query['endDate']) ?? db.now();
    final start = _parseDate(r.query['startDate']) ?? DateTime(end.year, end.month - 1, end.day, end.hour, end.minute);
    if (start.isAfter(end)) {
      return FakeResponse.error(400, 'REQUEST_REJECTED', 'La date de début doit précéder la date de fin.');
    }
    final rows = db.issuerTransactions.where((t) {
      final d = _issuerDate(t);
      return !d.isBefore(start) && d.isBefore(end);
    }).toList();
    return FakeResponse.ok({'success': true, 'transactions': rows});
  });

  // ---- Opérations (Partie 6 §1) ----
  api.on('GET', '/operations', (r) {
    if (r.query.containsKey('merchantId')) {
      return FakeResponse.error(403, 'FORBIDDEN', 'Vous n’avez pas accès aux opérations de ce marchand.');
    }
    final bad = _limitError(r.query, 100);
    if (bad != null) return bad;
    final status = r.query['status'] as String?;
    if (status != null && !_operationStatuses.contains(status)) {
      return FakeResponse.validation({
        'status': ['status must be one of the following values: ${_operationStatuses.join(', ')}'],
      });
    }
    final type = r.query['operationType'] as String?;
    if (type != null && !_operationTypes.contains(type)) {
      return FakeResponse.validation({
        'operationType': ['operationType must be one of the following values: ${_operationTypes.join(', ')}'],
      });
    }
    // `startDate` : `createdAt >= début du jour` ; `endDate` : `createdAt <= fin du jour` (@IsDateString).
    final dates = <String, DateTime>{};
    for (final key in const ['startDate', 'endDate']) {
      final v = r.query[key];
      if (v == null) continue;
      final d = _parseOperationDay('$v');
      if (d == null) {
        return FakeResponse.validation({
          key: ['$key must be a valid ISO 8601 date string'],
        });
      }
      dates[key] = d;
    }
    final start = dates['startDate'];
    final endDay = dates['endDate'];
    // Hypothèse du faux backend (le guide ne précise pas ce cas pour /operations) : même refus que le relevé.
    if (start != null && endDay != null && start.isAfter(endDay)) {
      return FakeResponse.error(400, 'REQUEST_REJECTED', 'La date de début doit précéder la date de fin.');
    }
    final dateOnlyEnd = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('${r.query['endDate']}');
    final end = endDay == null ? null : (dateOnlyEnd ? endDay.add(const Duration(days: 1)) : endDay);
    // `search` : `reference` ou `idempotencyKey` contient (insensible à la casse), ou `id` exact (§1.1).
    final search = (r.query['search'] as String?)?.toLowerCase();
    final list = db.operations
        .where((o) => status == null || o['status'] == status)
        .where((o) => type == null || o['type'] == type)
        .where((o) {
          if (start == null && end == null) return true;
          final created = DateTime.parse('${o['createdAt']}').toLocal();
          return (start == null || !created.isBefore(start)) &&
              (end == null || (dateOnlyEnd ? created.isBefore(end) : !created.isAfter(end)));
        })
        .where(
          (o) =>
              search == null ||
              o['id'] == r.query['search'] ||
              '${o['reference'] ?? ''}'.toLowerCase().contains(search) ||
              '${o['idempotencyKey'] ?? ''}'.toLowerCase().contains(search),
        )
        .toList();
    // Les `stats` portent sur tous les filtres actifs (pas sur la page).
    return FakeResponse.ok({'success': true, ...pageOf(list, r.query), 'stats': _stats(list)});
  });

  api.on('GET', '/operations/:id', (r) {
    final op = db.operationById(r.pathParams['id']!);
    if (op == null) return FakeResponse.error(404, 'NOT_FOUND', 'Opération introuvable.');
    final extra = db.operationDetails[op['id']] ?? const {};
    return FakeResponse.ok({
      'success': true,
      'data': {...op, 'quote': extra['quote'], 'movements': extra['movements'] ?? <Object>[]},
    });
  });

  // ---- Notifications (Partie 6 §2) ----
  int unread() => db.notifications.where((n) => n['readAt'] == null && n['archivedAt'] == null).length;

  api.on('GET', '/notifications', (r) {
    final bad = _limitError(r.query, 50);
    if (bad != null) return bad;
    final includeArchived = '${r.query['includeArchived']}' == 'true';
    final unreadOnly = '${r.query['unreadOnly']}' == 'true';
    final kind = r.query['kind'] as String?;
    const kinds = ['INFO', 'SUCCESS', 'WARNING', 'ERROR', 'FINANCIAL', 'SECURITY'];
    if (kind != null && !kinds.contains(kind)) {
      return FakeResponse.validation({
        'kind': ['kind must be one of the following values: ${kinds.join(', ')}'],
      });
    }
    final list = db.notifications
        .where((n) => includeArchived || n['archivedAt'] == null)
        .where((n) => !unreadOnly || n['readAt'] == null)
        .where((n) => kind == null || n['kind'] == kind)
        .toList();
    return FakeResponse.ok({'success': true, ...pageOf(list, r.query, maxLimit: 50), 'unreadCount': unread()});
  });

  api.on('GET', '/notifications/unread-count', (_) => FakeResponse.ok({'success': true, 'count': unread()}));

  api.on('POST', '/notifications/read-all', (_) {
    var marked = 0;
    for (final n in db.notifications) {
      if (n['readAt'] == null && n['archivedAt'] == null) {
        n['readAt'] = db.iso(db.now());
        marked++;
      }
    }
    return FakeResponse.ok({
      'success': true,
      'message': '$marked notification(s) marquée(s) comme lue(s).',
      'marked': marked,
    });
  });

  api.on('POST', '/notifications/archive-read', (_) {
    var archived = 0;
    for (final n in db.notifications) {
      if (n['readAt'] != null && n['archivedAt'] == null) {
        n['archivedAt'] = db.iso(db.now());
        archived++;
      }
    }
    return FakeResponse.ok({'success': true, 'message': '$archived notification(s) rangée(s).', 'archived': archived});
  });

  api.on('POST', '/notifications/:id/read', (r) {
    final n = db.notifications.where((n) => n['id'] == r.pathParams['id'] && n['readAt'] == null).firstOrNull;
    if (n == null) return FakeResponse.error(404, 'NOT_FOUND', 'Notification introuvable.');
    n['readAt'] = db.iso(db.now());
    return const FakeResponse.ok({'success': true, 'message': 'Notification marquée comme lue.'});
  });

  api.on('DELETE', '/notifications/:id', (r) {
    final n = db.notifications.where((n) => n['id'] == r.pathParams['id'] && n['archivedAt'] == null).firstOrNull;
    if (n == null) return FakeResponse.error(404, 'NOT_FOUND', 'Notification introuvable.');
    n['archivedAt'] = db.iso(db.now());
    n['readAt'] ??= db.iso(db.now());
    return const FakeResponse.ok({'success': true, 'message': 'Notification rangée.'});
  });

  // ---- Contenu hors API (promotions) ----
  api.on('GET', '/promotions', (r) {
    final placement = r.query['placement'];
    final items = db.adsEnabled ? db.promotions.where((p) => p['placement'] == placement).toList() : const [];
    return FakeResponse.ok({'items': items});
  });

  // ---- État et catalogue (Partie 6 §4, Partie 5 §3.2) ----
  api.on('GET', '/status', (_) {
    final services = [
      {
        'name': 'Électricité prépayée',
        'status': db.incident ? 'DOWN' : 'HEALTHY',
        'uptime': db.incident ? 97.2 : 99.9,
        'lastCheckedAt': db.iso(db.now()),
      },
      {'name': 'Portefeuilles mobiles', 'status': 'HEALTHY', 'uptime': 99.7, 'lastCheckedAt': db.iso(db.now())},
    ];
    return FakeResponse.ok({
      'success': true,
      'overall': db.incident ? 'partial_outage' : 'operational',
      'checkedAt': db.iso(db.now()),
      'services': services,
    });
  }, auth: false);

  api.on('GET', '/catalog/services', (_) {
    final data = [
      for (final s in _catalog)
        _offer(
          s,
          unavailable: db.incident && s.$1 == 'electricity-prepaid'
              ? 'Momentanément indisponible — nos équipes travaillent au rétablissement.'
              : null,
        ),
    ];
    return FakeResponse.ok({'success': true, 'data': data, 'count': data.length});
  });
}

/// (clé, libellé, kind, catégorie, amountMode, sources, min, max)
const _catalog = <(String, String, String, String?, String, List<String>, num, num)>[
  ('merchant:card:transfer', 'Transfert carte à carte', 'CARD_SERVICE', null, 'FREE', ['CUSTOMER_CARD'], 1000, 5000000),
  (
    'merchant:card:card-to-wallet',
    'Retrait vers un portefeuille mobile',
    'CARD_SERVICE',
    null,
    'FREE',
    ['CUSTOMER_CARD'],
    1000,
    1000000,
  ),
  (
    'wallet-to-card',
    'Recharge de carte depuis un portefeuille mobile',
    'CATALOG',
    'CARD',
    'FREE',
    ['CUSTOMER_EXTERNAL_CHANNEL'],
    500,
    1000000,
  ),
  (
    'mobile-topup',
    'Recharge téléphonique',
    'CATALOG',
    'TELECOM',
    'FREE',
    ['CUSTOMER_CARD', 'CUSTOMER_EXTERNAL_CHANNEL'],
    100,
    50000,
  ),
  (
    'mobile-data',
    'Forfait internet',
    'CATALOG',
    'TELECOM',
    'IMPOSED',
    ['CUSTOMER_CARD', 'CUSTOMER_EXTERNAL_CHANNEL'],
    100,
    100000,
  ),
  (
    'electricity-prepaid',
    'Électricité prépayée',
    'CATALOG',
    'ENERGY',
    'FREE',
    ['CUSTOMER_CARD', 'CUSTOMER_EXTERNAL_CHANNEL'],
    1000,
    500000,
  ),
  (
    'electricity-postpaid',
    'Facture d’électricité',
    'CATALOG',
    'ENERGY',
    'IMPOSED',
    ['CUSTOMER_CARD', 'CUSTOMER_EXTERNAL_CHANNEL'],
    1000,
    10000000,
  ),
  (
    'tv-subscription',
    'Abonnement télévision',
    'CATALOG',
    'TV',
    'IMPOSED',
    ['CUSTOMER_CARD', 'CUSTOMER_EXTERNAL_CHANNEL'],
    1000,
    200000,
  ),
  (
    'cash-withdrawal',
    'Retrait au guichet',
    'CATALOG',
    'CASH',
    'FREE',
    ['CUSTOMER_CARD', 'CUSTOMER_EXTERNAL_CHANNEL'],
    1000,
    500000,
  ),
];

Map<String, dynamic> _offer(
  (String, String, String, String?, String, List<String>, num, num) s, {
  String? unavailable,
}) {
  final (key, label, kind, category, mode, sources, min, max) = s;
  return {
    'key': key,
    'label': label,
    'kind': kind,
    'category': category,
    'amountMode': mode,
    'countryCodes': ['BJ'],
    'available': unavailable == null,
    'unavailableReason': unavailable,
    'options': [
      for (final src in sources)
        {
          'fundsSource': kind == 'CARD_SERVICE' ? null : src,
          'serviceSlug': key,
          'available': unavailable == null,
          'unavailableReason': unavailable,
          'limits': {'minAmount': min, 'maxAmount': max},
          'fee': null,
        },
    ],
  };
}

Map<String, dynamic> _stats(List<Map<String, dynamic>> ops) {
  int count(Set<String> s) => ops.where((o) => s.contains(o['status'])).length;
  num sum(Iterable<Map<String, dynamic>> l) => l.fold<num>(0, (a, o) => a + (o['amount'] as num));
  return {
    'totalOperations': ops.length,
    'successfulOperations': count({'SUCCESS'}),
    'failedOperations': count({'FAILED', 'CANCELLED', 'EXPIRED'}),
    'pendingOperations': count({'PENDING', 'PROCESSING', 'INITIALIZED', 'PENDING_APPROVAL'}),
    'todaysTotalOperations': 0,
    'totalAmount': sum(ops),
    'successfulAmount': sum(ops.where((o) => o['status'] == 'SUCCESS')),
    'todaysTotalAmount': 0,
    'currencyIsoCode': 'xof',
  };
}

const _mon = {
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

DateTime _issuerDate(Map<String, dynamic> t) {
  final p = '${t['transactionDate']}'.split('-');
  final h = '${t['transactionTimeHH24'] ?? '00:00:00'}'.split(':').map(int.parse).toList();
  return DateTime(int.parse(p[2]), _mon[p[1]]!, int.parse(p[0]), h[0], h[1], h[2]);
}

/// `AAAA-MM-JJ` = minuit UTC de ce jour (comme l'API) ; date-heure avec décalage acceptée.
DateTime? _parseDate(Object? v) {
  if (v == null) return null;
  final s = '$v';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return DateTime.parse('${s}T00:00:00Z').toLocal();
  return DateTime.tryParse(s)?.toLocal();
}
