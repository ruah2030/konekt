import '../fake_api.dart';

/// Connexion du porteur (`/auth/customer/*`, guide Partie 2 §2.2 à §2.6).
void registerAuthHandlers(FakeApi api) {
  final db = api.db;

  api.on('GET', '/auth/customer/channels', (_) {
    final channels = [
      for (final e in db.channels.entries) {'channel': e.key, 'available': e.value},
    ];
    final def = db.channels.entries.where((e) => e.value).map((e) => e.key).firstOrNull;
    return FakeResponse.ok({'success': true, 'channels': channels, 'defaultChannel': def});
  }, auth: false);

  api.on(
    'POST',
    '/auth/customer/login/init',
    (r) {
      final b = r.body;
      final cardId = '${b['cardCustomerId'] ?? ''}'.replaceAll(RegExp(r'\s'), '');
      final last4 = '${b['last4Digits'] ?? ''}';
      final fields = <String, List<String>>{
        if (!RegExp(r'^\d{6,20}$').hasMatch(cardId))
          'cardCustomerId': ["L'identifiant de carte compte 6 à 20 chiffres."],
        if (!RegExp(r'^\d{4}$').hasMatch(last4)) 'last4Digits': ['Quatre chiffres attendus.'],
        if ('${b['appId'] ?? ''}'.isEmpty) 'appId': ['appId should not be empty'],
      };
      if (RegExp('[oO]').hasMatch(cardId)) {
        return FakeResponse.error(
          400,
          'REQUEST_REJECTED',
          'Identifiant de carte invalide : chiffres uniquement (vérifiez qu’aucune lettre « O » n’a été saisie à la place du zéro).',
        );
      }
      if (fields.isNotEmpty) return FakeResponse.validation(fields);
      if (b['appId'] == 'bad') return FakeResponse.error(401, 'UNAUTHENTICATED', 'Application non reconnue.');
      if (last4 == '0000') return FakeResponse.error(401, 'UNAUTHENTICATED', 'Informations de connexion invalides.');
      if (db.loginCodesThisHour >= 3) {
        return FakeResponse.error(400, 'REQUEST_REJECTED', 'Trop de demandes de code. Réessayez dans une heure.');
      }
      final wanted = b['doubleAuthMethod'] as String?;
      if (wanted != null && db.channels[wanted] != true) {
        return FakeResponse.error(
          400,
          'REQUEST_REJECTED',
          'Ce canal est momentanément indisponible. Choisissez-en un autre.',
        );
      }
      final used = wanted != null ? [wanted] : db.channels.entries.where((e) => e.value).map((e) => e.key).toList();
      db
        ..sessionCardId = cardId
        ..last4 = last4
        ..loginCodesThisHour += 1;
      db.loginCodes[cardId] = {'expiresAt': db.now().add(const Duration(minutes: 5)), 'attemptsLeft': 3};
      return FakeResponse.ok({
        'success': true,
        'message': 'Code envoyé.',
        'channelsUsed': used,
        'maskedContacts': [for (final c in used) c == 'EMAIL' ? db.maskedEmail : db.maskedPhone],
        'expiryMinutes': 5,
      });
    },
    auth: false,
    fields: {'cardCustomerId', 'last4Digits', 'doubleAuthMethod', 'appId'},
  );

  api.on(
    'POST',
    '/auth/customer/login/confirm',
    (r) {
      final b = r.body;
      final cardId = '${b['cardCustomerId'] ?? ''}'.replaceAll(RegExp(r'\s'), '');
      final code = '${b['code'] ?? ''}';
      if (!RegExp(r'^\d{6}$').hasMatch(code)) {
        return FakeResponse.validation({
          'code': ['Le code comporte six chiffres.'],
        });
      }
      final pending = db.loginCodes[cardId];
      if (pending == null || b['last4Digits'] != db.last4) {
        return FakeResponse.error(
          401,
          'UNAUTHENTICATED',
          'Code incorrect, expiré ou déjà utilisé. Demandez un nouveau code.',
        );
      }
      if (db.now().isAfter(pending['expiresAt'] as DateTime)) {
        db.loginCodes.remove(cardId);
        return FakeResponse.error(401, 'UNAUTHENTICATED', 'Ce code a expiré. Demandez-en un nouveau.');
      }
      if (code == '000000') {
        final left = (pending['attemptsLeft'] as int) - 1;
        pending['attemptsLeft'] = left;
        if (left <= 0) db.loginCodes.remove(cardId);
        return FakeResponse.error(
          401,
          'UNAUTHENTICATED',
          left > 0
              ? 'Code incorrect. $left essai(s) restant(s).'
              : 'Code inutilisable après 3 essais. Demandez un nouveau code.',
        );
      }
      if (db.cardStatus == 'LostOrStolen') {
        return FakeResponse.error(
          403,
          'FORBIDDEN',
          'Cette carte a été déclarée perdue ou volée. Contactez le support : vos fonds peuvent être transférés sur une nouvelle carte.',
        );
      }
      db.loginCodes.remove(cardId);
      final t = db.issueTokens();
      final device = b['device'];
      if (device is Map) {
        final current = db.devices.firstWhere((d) => d['isCurrent'] == true);
        current
          ..['type'] = device['type'] ?? current['type']
          ..['label'] = device['label'] ?? current['label']
          ..['notificationsEnabled'] = device['fcmToken'] != null
          ..['lastSeenAt'] = db.iso(db.now());
      }
      return FakeResponse.ok({
        'success': true,
        'message': 'Connexion réussie.',
        'tokens': {
          'sessionToken': t.session,
          'refreshToken': t.refresh,
          'sessionId': t.sessionId,
          'expiresIn': 1800,
          'refreshExpiresIn': 2592000,
        },
        'card': {
          'cardCustomerId': db.sessionCardId,
          'last4Digits': db.last4,
          'status': db.cardStatus == 'Deactivated' ? 'Inactive' : db.cardStatus,
        },
        'holder': {'firstName': db.holder['firstName'], 'lastName': db.holder['lastName']},
        'hasPin': db.hasPin,
        'isExternalCard': db.isExternalCard,
      });
    },
    auth: false,
    fields: {
      'cardCustomerId',
      'last4Digits',
      'appId',
      'code',
      'merchantReferralCode',
      'countryCode',
      'stateRegionCode',
      'device',
    },
  );

  api.on(
    'POST',
    '/auth/customer/refresh',
    (r) {
      if (!db.consumeRefreshToken('${r.body['refreshToken']}')) {
        return FakeResponse.error(401, 'UNAUTHENTICATED', 'Jeton de renouvellement invalide, expiré ou déjà utilisé.');
      }
      final t = db.issueTokens();
      return FakeResponse.ok({
        'success': true,
        'sessionToken': t.session,
        'refreshToken': t.refresh,
        'sessionId': t.sessionId,
        'expiresIn': 1800,
        'refreshExpiresIn': 2592000,
      });
    },
    auth: false,
    fields: {'refreshToken'},
  );

  api.on('POST', '/auth/customer/logout', (r) {
    db.revokeSessionToken(r.bearer);
    return const FakeResponse.ok({'success': true, 'message': 'Déconnexion effectuée.'});
  });

  api.on('POST', '/auth/customer/logout-all', (_) {
    final closed = db.devices.where((d) => d['hasActiveSession'] == true).length;
    db.revokeAll();
    for (final d in db.devices) {
      d['hasActiveSession'] = false;
    }
    return FakeResponse.ok({'success': true, 'closed': closed});
  });
}
