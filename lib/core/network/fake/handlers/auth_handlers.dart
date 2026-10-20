import '../fake_api.dart';

/// Invitation, liste d'attente, connexion par carte + OTP, session.
void registerAuthHandlers(FakeApi api) {
  final db = api.db;

  api.on('POST', '/v1/invitations/verify', (r) {
    final code = '${r.body['code'] ?? ''}'.replaceAll('-', '').toUpperCase();
    if (code.length != 8) {
      return FakeResponse.error(422, 'VALIDATION_FAILED', 'Le code compte 8 caractères.');
    }
    if (RegExp(r'^0+$').hasMatch(code) || code.startsWith('XXXX')) {
      return FakeResponse.error(
        422,
        'REQUEST_REJECTED',
        'Code invalide ou déjà utilisé. Vérifiez-le auprès de la personne qui vous l’a donné.',
      );
    }
    return const FakeResponse.ok({'inviterName': 'Rodrigue A.'});
  }, auth: false);

  api.on('POST', '/v1/waitlist', (r) {
    final msisdn = '${r.body['msisdn'] ?? ''}'.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\+?\d{8,15}$').hasMatch(msisdn)) {
      return FakeResponse.error(422, 'VALIDATION_FAILED', 'Numéro de téléphone invalide.');
    }
    return FakeResponse.ok({'position': ++db.waitlistPosition});
  }, auth: false);

  Map<String, dynamic> challengeJson(String id) {
    final c = db.challenges[id]!;
    return {
      'challengeId': id,
      'channel': c['channel'],
      'maskedDestination': c['channel'] == 'EMAIL' ? db.holder['email'] : db.holder['maskedPhone'],
      'expiresAt': (c['expiresAt'] as DateTime).toIso8601String(),
      'sendsLeft': 3 - db.otpSendsThisHour,
    };
  }

  api.on('POST', '/v1/auth/login', (r) {
    final cardId = '${r.body['cardId'] ?? ''}'.replaceAll(RegExp(r'\s'), '');
    final last4 = '${r.body['last4'] ?? ''}';
    final channel = '${r.body['channel'] ?? 'SMS'}';
    if (RegExp('[oO]').hasMatch(cardId)) {
      return FakeResponse.error(
        422,
        'REQUEST_REJECTED',
        'Chiffres uniquement : vérifiez qu’aucune lettre « O » n’a été saisie à la place du zéro.',
      );
    }
    if (!RegExp(r'^\d{6,20}$').hasMatch(cardId)) {
      return FakeResponse.error(422, 'VALIDATION_FAILED', "L'identifiant de carte compte 6 à 20 chiffres.");
    }
    if (!RegExp(r'^\d{4}$').hasMatch(last4)) {
      return FakeResponse.error(422, 'VALIDATION_FAILED', 'Quatre chiffres attendus.');
    }
    if (last4 == '0000') {
      return FakeResponse.error(401, 'UNAUTHENTICATED', 'Identifiant ou chiffres incorrects.');
    }
    if (channel == 'WHATSAPP') {
      return FakeResponse.error(422, 'REQUEST_REJECTED', 'WhatsApp momentanément indisponible.');
    }
    if (db.otpSendsThisHour >= 3) {
      return FakeResponse.error(429, 'REQUEST_REJECTED', 'Trop de demandes de code. Réessayez dans une heure.');
    }
    db
      ..sessionCardId = cardId
      ..last4 = last4
      ..otpSendsThisHour += 1;
    final id = db.id('chl_', 10);
    db.challenges[id] = {'expiresAt': db.now().add(const Duration(minutes: 5)), 'tries': 3, 'channel': channel};
    return FakeResponse.ok(challengeJson(id));
  }, auth: false);

  api.on('POST', '/v1/auth/otp/resend', (r) {
    final id = '${r.body['challengeId']}';
    final c = db.challenges[id];
    if (c == null) return FakeResponse.error(404, 'NOT_FOUND', 'Demande expirée. Recommencez la connexion.');
    if (db.otpSendsThisHour >= 3) {
      return FakeResponse.error(429, 'REQUEST_REJECTED', 'Trop de demandes de code. Réessayez dans une heure.');
    }
    db.otpSendsThisHour += 1;
    c
      ..['expiresAt'] = db.now().add(const Duration(minutes: 5))
      ..['tries'] = 3;
    return FakeResponse.ok(challengeJson(id));
  }, auth: false);

  api.on('POST', '/v1/auth/otp/verify', (r) {
    final id = '${r.body['challengeId']}';
    final code = '${r.body['code']}';
    final c = db.challenges[id];
    if (c == null) return FakeResponse.error(404, 'NOT_FOUND', 'Demande expirée. Recommencez la connexion.');
    if (db.now().isAfter(c['expiresAt'] as DateTime)) {
      return FakeResponse.error(401, 'UNAUTHENTICATED', 'Ce code a expiré. Demandez-en un nouveau.');
    }
    if ((c['tries'] as int) <= 0) {
      return FakeResponse.error(401, 'UNAUTHENTICATED', 'Code inutilisable après 3 essais. Demandez un nouveau code.');
    }
    if (code == '000000') {
      final t = (c['tries'] as int) - 1;
      c['tries'] = t;
      return FakeResponse.error(
        401,
        'UNAUTHENTICATED',
        t > 0
            ? 'Code incorrect. $t essai(s) restant(s).'
            : 'Code inutilisable après 3 essais. Demandez un nouveau code.',
        details: {'triesLeft': t},
      );
    }
    db.challenges.remove(id);
    final tokens = db.issueTokens();
    final device = r.body['device'];
    if (device is Map) {
      final current = db.devices.firstWhere((d) => d['current'] == true);
      current['label'] = device['label'] ?? current['label'];
      current['platform'] = device['platform'] ?? current['platform'];
      current['lastSeenAt'] = db.now().toIso8601String();
    }
    return FakeResponse.ok({'accessToken': tokens.access, 'refreshToken': tokens.refresh, 'hasPin': db.hasPin});
  }, auth: false);

  api.on('POST', '/v1/auth/refresh', (r) {
    final rt = '${r.body['refreshToken']}';
    if (!db.consumeRefreshToken(rt)) {
      return FakeResponse.error(401, 'UNAUTHENTICATED', 'Votre session a expiré. Reconnectez-vous.');
    }
    final tokens = db.issueTokens();
    return FakeResponse.ok({'accessToken': tokens.access, 'refreshToken': tokens.refresh});
  }, auth: false);

  api.on('GET', '/v1/auth/session', (_) => FakeResponse.ok({'hasPin': db.hasPin}));

  api.on('POST', '/v1/auth/logout', (r) {
    db.revokeAccessToken(r.bearer);
    return const FakeResponse.noContent();
  });

  api.on('POST', '/v1/auth/logout-all', (_) {
    final n = db.devices.length;
    db
      ..revokeAll()
      ..devices.removeWhere((d) => d['current'] != true);
    return FakeResponse.ok({'closedSessions': n});
  });
}
