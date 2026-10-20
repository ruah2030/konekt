import '../fake_api.dart';

/// Code secret : vérification SMS+e-mail, création, contrôle, changement, réinitialisation, statut.
void registerPinHandlers(FakeApi api) {
  final db = api.db;
  const weakMessage = 'Code trop simple : évitez les chiffres identiques et les suites.';
  const maxVerificationTries = 3;
  var verificationTries = maxVerificationTries;

  bool isWeak(String p) => RegExp(r'^(\d)\1{5}$').hasMatch(p) || '0123456789'.contains(p) || '9876543210'.contains(p);
  bool isPinFormat(String p) => RegExp(r'^\d{6}$').hasMatch(p);

  FakeResponse? validateNewPin(String pin) {
    if (!isPinFormat(pin)) return FakeResponse.error(422, 'VALIDATION_FAILED', 'Le code secret compte 6 chiffres.');
    if (isWeak(pin)) return FakeResponse.error(422, 'PIN_TOO_WEAK', weakMessage);
    return null;
  }

  FakeResponse? checkVerificationToken(Object? token) {
    if (db.pinVerificationToken == null || token != db.pinVerificationToken) {
      return FakeResponse.error(403, 'FORBIDDEN', 'Vérification expirée. Recommencez.');
    }
    return null;
  }

  /// Contrôle le PIN actuel : décompte des essais et verrouillage de 15 min.
  FakeResponse? checkCurrentPin(String pin) {
    if (db.pin == null) return FakeResponse.error(422, 'REQUEST_REJECTED', "Vous n'avez pas encore de code secret.");
    final lock = db.pinLockedUntil;
    if (lock != null && db.now().isBefore(lock)) {
      final minutes = (lock.difference(db.now()).inSeconds / 60).ceil();
      return FakeResponse.error(
        403,
        'FORBIDDEN',
        'Réessayez dans $minutes minute(s), ou réinitialisez votre code secret.',
        details: {'lockedUntil': lock.toIso8601String()},
      );
    }
    if (pin != db.pin) {
      final t = db.pinTries - 1;
      if (t <= 0) {
        db
          ..pinTries = 5
          ..pinLockedUntil = db.now().add(const Duration(minutes: 15));
        return FakeResponse.error(
          403,
          'FORBIDDEN',
          'Trop de codes erronés. Réessayez dans 15 minutes, ou réinitialisez votre code secret.',
          details: {'triesLeft': 0, 'lockedUntil': db.pinLockedUntil!.toIso8601String()},
        );
      }
      db.pinTries = t;
      return FakeResponse.error(
        403,
        'FORBIDDEN',
        'Code secret incorrect. $t essai(s) avant verrouillage.',
        details: {'triesLeft': t},
      );
    }
    db.pinTries = 5;
    return null;
  }

  api.on('POST', '/v1/pin/verification', (_) {
    verificationTries = maxVerificationTries;
    db.pinVerificationToken = null;
    return FakeResponse.ok({
      'maskedDestinations': [db.holder['maskedPhone'], db.holder['email']],
    });
  });

  // NB : 422 et non 401, pour ne pas déclencher le rafraîchissement de session de l'AuthInterceptor.
  api.on('POST', '/v1/pin/verification/confirm', (r) {
    final code = '${r.body['code'] ?? ''}';
    if (!isPinFormat(code)) return FakeResponse.error(422, 'VALIDATION_FAILED', 'Le code compte 6 chiffres.');
    if (verificationTries <= 0) {
      return FakeResponse.error(422, 'PIN_CODE_INVALID', 'Code inutilisable après 3 essais. Demandez un nouveau code.');
    }
    if (code == '000000') {
      verificationTries -= 1;
      return FakeResponse.error(
        422,
        'PIN_CODE_INVALID',
        verificationTries > 0
            ? 'Code incorrect, $verificationTries essai(s) restant(s).'
            : 'Code inutilisable après 3 essais. Demandez un nouveau code.',
        details: {'triesLeft': verificationTries},
      );
    }
    final token = db.id('pvt_', 16);
    db.pinVerificationToken = token;
    return FakeResponse.ok({'verificationToken': token});
  });

  api.on('POST', '/v1/pin', (r) {
    final pin = '${r.body['pin'] ?? ''}';
    final err = checkVerificationToken(r.body['verificationToken']) ?? validateNewPin(pin);
    if (err != null) return err;
    if (db.hasPin) return FakeResponse.error(422, 'REQUEST_REJECTED', 'Un code secret existe déjà.');
    db
      ..pin = pin
      ..pinTries = 5
      ..pinLockedUntil = null
      ..pinVerificationToken = null;
    return const FakeResponse.noContent();
  });

  api.on('POST', '/v1/pin/check', (r) => checkCurrentPin('${r.body['pin'] ?? ''}') ?? const FakeResponse.noContent());

  api.on('PUT', '/v1/pin', (r) {
    final current = '${r.body['currentPin'] ?? ''}';
    final next = '${r.body['newPin'] ?? ''}';
    final err = checkCurrentPin(current);
    if (err != null) return err;
    if (next == current) {
      return FakeResponse.error(422, 'REQUEST_REJECTED', "Le nouveau code doit être différent de l'ancien.");
    }
    final invalid = validateNewPin(next);
    if (invalid != null) return invalid;
    db.pin = next;
    return const FakeResponse.noContent();
  });

  api.on('POST', '/v1/pin/reset', (r) {
    final pin = '${r.body['pin'] ?? ''}';
    final err = checkVerificationToken(r.body['verificationToken']) ?? validateNewPin(pin);
    if (err != null) return err;
    db
      ..pin = pin
      ..pinTries = 5
      ..pinLockedUntil = null
      ..pinVerificationToken = null;
    return const FakeResponse.noContent();
  });

  api.on('GET', '/v1/pin/status', (_) {
    final lock = db.pinLockedUntil;
    final locked = lock != null && db.now().isBefore(lock);
    return FakeResponse.ok({
      'hasPin': db.hasPin,
      'triesLeft': db.pinTries,
      'lockedUntil': locked ? lock.toIso8601String() : null,
    });
  });
}
