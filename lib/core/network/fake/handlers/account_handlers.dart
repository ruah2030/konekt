import '../fake_api.dart';

/// Pagination par curseur (= index de départ) sur une liste en mémoire.
Map<String, dynamic> paginate(List<Map<String, dynamic>> all, Map<String, dynamic> query) {
  final limit = int.tryParse('${query['limit'] ?? 20}') ?? 20;
  final start = int.tryParse('${query['cursor'] ?? 0}') ?? 0;
  final end = (start + limit).clamp(0, all.length);
  return {'items': all.sublist(start.clamp(0, all.length), end), 'nextCursor': end < all.length ? '$end' : null};
}

/// Lectures partagées : titulaire, carte, solde, historiques, notifications, contenu.
void registerAccountHandlers(FakeApi api) {
  final db = api.db;

  api.on('GET', '/v1/me', (_) => FakeResponse.ok(db.holder));
  api.on('GET', '/v1/card', (_) => FakeResponse.ok(db.cardJson()));
  api.on('GET', '/v1/card/balance', (_) {
    final available = switch (db.cardStatus) {
      'PRE_ACTIVE' => 0,
      _ => db.balance,
    };
    return FakeResponse.ok({'available': available, 'currency': 'XOF', 'asOf': db.now().toIso8601String()});
  });
  api.on('GET', '/v1/card/transactions', (r) {
    final list = db.cardStatus == 'PRE_ACTIVE' ? <Map<String, dynamic>>[] : db.transactions;
    return FakeResponse.ok(paginate(list, r.query));
  });
  api.on('GET', '/v1/operations', (r) => FakeResponse.ok(paginate(db.operations, r.query)));
  api.on('GET', '/v1/operations/:id', (r) {
    final op = db.operations.where((o) => o['id'] == r.pathParams['id']).firstOrNull;
    return op == null ? FakeResponse.error(404, 'NOT_FOUND', 'Opération introuvable.') : FakeResponse.ok(op);
  });

  api.on('GET', '/v1/notifications', (_) => FakeResponse.ok({'items': db.notifications}));
  api.on('POST', '/v1/notifications/read-all', (_) {
    for (final n in db.notifications) {
      n['read'] = true;
    }
    return const FakeResponse.noContent();
  });
  api.on('POST', '/v1/notifications/:id/read', (r) {
    for (final n in db.notifications) {
      if (n['id'] == r.pathParams['id']) n['read'] = true;
    }
    return const FakeResponse.noContent();
  });

  api.on('GET', '/v1/promotions', (r) {
    final placement = r.query['placement'];
    final items = db.adsEnabled ? db.promotions.where((p) => p['placement'] == placement).toList() : const [];
    return FakeResponse.ok({'items': items});
  }, auth: false);

  api.on(
    'GET',
    '/v1/status',
    (_) => FakeResponse.ok({
      'incidents': [
        if (db.incident)
          {'id': 'inc_1', 'message': 'Incident chez un opérateur : certains paiements peuvent être ralentis.'},
      ],
    }),
    auth: false,
  );
}
