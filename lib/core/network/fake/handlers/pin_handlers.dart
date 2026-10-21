import '../fake_api.dart';

/// Code secret du porteur (`/auth/customer/pin*`, guide §2.7) et liste d'attente (hors API).
///
/// Valeurs utiles : tout code de vérification à 6 chiffres est accepté sauf `000000` (faux).
void registerPinHandlers(FakeApi api) {
  final db = api.db;
  const maxPinAttempts = 5;
  const lockDuration = Duration(minutes: 15);
  const codeValidity = Duration(minutes: 5);

  /// Demandes de code (setup/reset) de la dernière minute : 5 au maximum.
  final codeRequests = <DateTime>[];

  /// Liste d'attente (hors API) : numéro → position.
  final waitlist = <String, int>{};

  bool isWeak(String pin) =>
      RegExp(r'^(\d)\1{5}$').hasMatch(pin) || '0123456789'.contains(pin) || '9876543210'.contains(pin);

  FakeResponse weakPin() => FakeResponse.error(
    400,
    'PIN_TOO_WEAK',
    'Code secret trop simple : évitez six chiffres identiques et les suites (123456, 987654…).',
  );

  /// Champs `pin` / `code` / `currentPin` : 6 chiffres.
  FakeResponse? validate(Map<String, dynamic> b, List<String> names) {
    final fields = <String, List<String>>{
      for (final n in names)
        if (!RegExp(r'^\d{6}$').hasMatch('${b[n] ?? ''}'))
          n: [n == 'code' ? 'Le code de vérification comporte six chiffres.' : 'Le code secret comporte six chiffres.'],
    };
    return fields.isEmpty ? null : FakeResponse.validation(fields);
  }

  FakeResponse? lockRefusal() {
    final until = db.pinLockedUntil;
    if (until == null || !db.now().isBefore(until)) return null;
    final minutes = (until.difference(db.now()).inSeconds / 60).ceil();
    return FakeResponse.error(
      403,
      'FORBIDDEN',
      'Trop de codes erronés. Réessayez dans $minutes minute(s), ou réinitialisez votre code.',
    );
  }

  /// Envoi d'un code de vérification (`setup` | `reset`) sur tous les contacts du dossier.
  FakeResponse sendCode(String purpose) {
    final now = db.now();
    codeRequests.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (codeRequests.length >= 5) {
      return FakeResponse.error(400, 'PIN_CODE_RATE_LIMITED', 'Trop de demandes de code. Patientez une minute.');
    }
    codeRequests.add(now);
    db.pinCode = {'purpose': purpose, 'expiresAt': now.add(codeValidity), 'attemptsLeft': 3, 'used': false};
    return FakeResponse.ok({
      'success': true,
      'channelsUsed': ['SMS', 'EMAIL'],
      'maskedContacts': [db.maskedPhone, db.maskedEmail],
      'expiryMinutes': codeValidity.inMinutes,
    });
  }

  /// Vérifie le code reçu sans le consommer. Un code faux (`000000`) décompte un essai.
  FakeResponse? checkCode(String code, String purpose) {
    final pc = db.pinCode;
    if (pc == null || pc['purpose'] != purpose) {
      return FakeResponse.error(400, 'PIN_CODE_EXPIRED', 'Aucun code en cours de validité. Demandez un nouveau code.');
    }
    if (pc['used'] == true) {
      return FakeResponse.error(400, 'PIN_CODE_ALREADY_USED', 'Ce code a déjà été utilisé. Demandez un nouveau code.');
    }
    if (db.now().isAfter(pc['expiresAt'] as DateTime)) {
      return FakeResponse.error(400, 'PIN_CODE_EXPIRED', 'Ce code a expiré. Demandez un nouveau code.');
    }
    final left = pc['attemptsLeft'] as int;
    if (left <= 0) {
      return FakeResponse.error(
        400,
        'PIN_CODE_EXHAUSTED',
        "Trop d'essais : ce code n'est plus utilisable. Demandez un nouveau code.",
      );
    }
    if (code == '000000') {
      pc['attemptsLeft'] = left - 1;
      if (left - 1 <= 0) {
        return FakeResponse.error(
          400,
          'PIN_CODE_EXHAUSTED',
          "Trop d'essais : ce code n'est plus utilisable. Demandez un nouveau code.",
        );
      }
      return FakeResponse.error(
        400,
        'PIN_CODE_INVALID',
        'Code de vérification incorrect.',
        details: {'attemptsLeft': left - 1},
      );
    }
    return null;
  }

  void definePin(String pin) {
    db.pinCode?['used'] = true;
    db
      ..pin = pin
      ..pinAttemptsLeft = maxPinAttempts
      ..pinLockedUntil = null;
  }

  // ---------------- Création (§2.7.1) ----------------
  api.on('POST', '/auth/customer/pin/setup/request', (_) {
    if (db.hasPin) {
      return FakeResponse.error(400, 'PIN_ALREADY_DEFINED', 'Un code secret est déjà défini pour cette carte.');
    }
    return sendCode('setup');
  }, fields: const <String>{});

  api.on('POST', '/auth/customer/pin', (r) {
    final b = r.body;
    final invalid = validate(b, ['pin', 'code']);
    if (invalid != null) return invalid;
    if (db.hasPin) {
      return FakeResponse.error(400, 'PIN_ALREADY_DEFINED', 'Un code secret est déjà défini pour cette carte.');
    }
    final pin = '${b['pin']}';
    // Le code reçu reste valable si le PIN est refusé.
    if (isWeak(pin)) return weakPin();
    final refused = checkCode('${b['code']}', 'setup');
    if (refused != null) return refused;
    definePin(pin);
    return const FakeResponse.created({'success': true, 'message': 'Code secret défini.'});
  }, fields: {'pin', 'code'});

  // ---------------- Changement (§2.7.2) ----------------
  api.on('POST', '/auth/customer/pin/change', (r) {
    final b = r.body;
    final invalid = validate(b, ['currentPin', 'pin']);
    if (invalid != null) return invalid;
    if (!db.hasPin) {
      return FakeResponse.error(400, 'REQUEST_REJECTED', "Aucun code secret n'est encore défini.");
    }
    final locked = lockRefusal();
    if (locked != null) return locked;
    final pin = '${b['pin']}';
    if (isWeak(pin)) return weakPin();
    if (b['currentPin'] != db.pin) {
      db.pinAttemptsLeft -= 1;
      if (db.pinAttemptsLeft <= 0) {
        db
          ..pinAttemptsLeft = 0
          ..pinLockedUntil = db.now().add(lockDuration);
        return lockRefusal()!;
      }
      return FakeResponse.error(
        403,
        'FORBIDDEN',
        'Code secret incorrect — ${db.pinAttemptsLeft} tentative(s) restante(s).',
      );
    }
    db.pinAttemptsLeft = maxPinAttempts;
    if (pin == db.pin) {
      return FakeResponse.error(400, 'REQUEST_REJECTED', "Le nouveau code doit être différent de l'ancien.");
    }
    db.pin = pin;
    return const FakeResponse.ok({'success': true, 'message': 'Code secret modifié.'});
  }, fields: {'currentPin', 'pin'});

  // ---------------- Oubli (§2.7.3) ----------------
  api.on('POST', '/auth/customer/pin/reset/request', (_) {
    if (!db.hasPin) {
      return FakeResponse.error(400, 'REQUEST_REJECTED', "Aucun code secret n'est encore défini.");
    }
    return sendCode('reset');
  }, fields: const <String>{});

  api.on('POST', '/auth/customer/pin/reset/confirm', (r) {
    final b = r.body;
    final invalid = validate(b, ['code', 'pin']);
    if (invalid != null) return invalid;
    final pin = '${b['pin']}';
    if (isWeak(pin)) return weakPin();
    final refused = checkCode('${b['code']}', 'reset');
    if (refused != null) return refused;
    // La réinitialisation lève aussi le verrouillage.
    definePin(pin);
    return const FakeResponse.ok({'success': true, 'message': 'Code secret réinitialisé.'});
  }, fields: {'code', 'pin'});

  // ---------------- Liste d'attente ----------------
  // Route HORS API CardConnect v2 : servie uniquement par le faux backend.
  // L'API réelle n'a pas de liste d'attente ; l'écran « Obtenir une invitation » l'appelle
  // via `WaitlistRepository`, à rebrancher le jour où un service dédié existera.
  api.on(
    'POST',
    '/waitlist',
    (r) {
      final msisdn = '${r.body['msisdn'] ?? ''}'.replaceAll(RegExp(r'[\s-]'), '');
      if (!RegExp(r'^\+?\d{8,15}$').hasMatch(msisdn)) {
        return FakeResponse.validation({
          'msisdn': ['Numéro de téléphone invalide.'],
        });
      }
      final position = waitlist.putIfAbsent(msisdn, () => 1287 + waitlist.length);
      return FakeResponse.created({'success': true, 'position': position});
    },
    auth: false,
    fields: {'msisdn'},
  );
}
