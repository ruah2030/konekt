import '../fake_api.dart';
import '../fake_db.dart';
import 'account_handlers.dart';

/// Paiements : sorties d'argent par carte (Partie 4 §6 à §12), catalogue (Partie 5),
/// portefeuilles externes (Partie 6 §3.1).
///
/// Valeurs de démo :
/// - cartes destinataires : `121436999` (Afiavi Sossou), `121437000` (Koffi Agbodjan),
///   `121436555` (suspendue) ; toute autre carte → 404 ;
/// - OTP d'opération / code B-MO : tout code sauf `000000` (ou `0000`) ;
/// - numéro se terminant par `0000` : sans compte B-MO / abonné inconnu ;
/// - payeur Mobile Money se terminant par `9999` : refuse la demande sur son téléphone ;
/// - montant `99999` (transfert, retrait) ou bénéficiaire mobile se terminant par `9999` :
///   sort indéterminé (500 « NE LA RELANCEZ PAS ») ;
/// - compteur se terminant par `9999` : service non rendu, remboursé (500).
void registerPaymentHandlers(FakeApi api) {
  final db = api.db;

  /// État hors format API, par opération : OTP, attente du payeur, code B-MO, etc.
  final meta = <String, Map<String, dynamic>>{};

  /// Horodatages des devis (plafond horaire `QUOTE_RATE_LIMIT`).
  final quoteTimes = <DateTime>[];

  // ---------------------------------------------------------------- PIN (§9, Partie 5 §2.4)
  FakeResponse? verifyPin(String? pin) {
    if (!db.hasPin) return _rejected('Aucun code secret n’a encore été défini pour ce compte.');
    final now = db.now();
    final until = db.pinLockedUntil;
    if (until != null) {
      if (now.isBefore(until)) {
        final minutes = (until.difference(now).inSeconds / 60).ceil();
        return FakeResponse.error(
          403,
          'FORBIDDEN',
          'Trop de codes erronés. Réessayez dans $minutes minute(s), ou réinitialisez votre code.',
        );
      }
      db
        ..pinLockedUntil = null
        ..pinAttemptsLeft = 5;
    }
    if (pin != db.pin) {
      db.pinAttemptsLeft -= 1;
      if (db.pinAttemptsLeft <= 0) {
        db
          ..pinLockedUntil = now.add(const Duration(minutes: 15))
          ..pinAttemptsLeft = 5;
        return FakeResponse.error(
          403,
          'FORBIDDEN',
          'Trop de codes erronés. Votre compte est bloqué pendant 15 minutes. Vous pouvez aussi réinitialiser votre code.',
        );
      }
      return FakeResponse.error(403, 'FORBIDDEN', 'Code incorrect — ${db.pinAttemptsLeft} tentative(s) restante(s).');
    }
    db.pinAttemptsLeft = 5;
    return null;
  }

  // ---------------------------------------------------------------- Opérations : lecture
  /// `OperationStatusResponseDto` (§11).
  Map<String, dynamic> statusDto(Map<String, dynamic> op) {
    final m = meta[op['id']] ?? const {};
    final status = op['status'] as String;
    final service = op['service'] as Map?;
    return {
      'success': true,
      'operationId': op['id'],
      'reference': op['reference'],
      'type': op['type'],
      'status': status,
      'initiationMode': op['initiationMode'],
      'amount': op['amount'],
      'fee': op['fee'],
      'amountDebited': op['amountDebited'],
      'amountCredited': op['amountCredited'],
      'reason': op['failureReason'] ?? op['cancellationReason'],
      'awaiting': status == 'PENDING' ? m['awaiting'] : null,
      'cards': [
        for (final c in (op['cards'] as List).cast<Map<String, dynamic>>())
          {'role': c['role'], 'last4': c['cardLast4'], 'holderName': c['holderName']},
      ],
      'service': service == null ? null : {'slug': service['slug'], 'label': service['label']},
      'merchantName': 'Boutique Cotonou Centre',
      'parties': op['parties'],
      'initiatedBy': {'type': 'customer', 'name': db.holderName},
      'createdAt': op['createdAt'],
      'approvedAt': op['approvedAt'],
    };
  }

  void touch(Map<String, dynamic> op, String status) {
    op['status'] = status;
    op['updatedAt'] = db.iso(db.now());
    if (status == 'SUCCESS') op['approvedAt'] = db.iso(db.now());
  }

  void addMovement(String opId, num amount, String direction, String label) {
    final d = db.operationDetails.putIfAbsent(opId, () => {'quote': null, 'movements': <Map<String, dynamic>>[]});
    (d['movements'] as List).add({
      'id': db.id('clwe'),
      'amount': amount,
      'direction': direction,
      'label': label,
      'at': db.iso(db.now()),
    });
  }

  // ---------------------------------------------------------------- Catalogue : exécution
  /// Service rendu (carte déjà débitée, ou portefeuille validé).
  void deliver(Map<String, dynamic> op) {
    final m = meta[op['id']]!;
    final service = m['service'] as String;
    final amount = op['amount'] as num;
    if (service == 'wallet-to-card') {
      db.balance += amount;
      db.addIssuerTransaction('Rechargement depuis ${m['channelLabel']}', amount);
      addMovement(op['id'] as String, amount, 'CREDIT', 'Recharge de la carte •••• ${db.last4}');
    }
    m['providerReference'] = '${2089700000 + db.now().millisecondsSinceEpoch % 99999}';
    touch(op, 'SUCCESS');
    db.addNotification(
      _successTitle(service),
      _successMessage(service, op, m),
      kind: 'FINANCIAL',
      linkType: 'operation',
      linkId: op['id'] as String,
    );
  }

  /// Recalcule l'état d'une opération qui dépend du temps (validation sur téléphone, code B-MO).
  void settle(Map<String, dynamic> op) {
    final m = meta[op['id']];
    if (m == null || op['status'] != 'PENDING') return;
    final now = db.now();
    switch (m['awaiting']) {
      case 'PAYER_APPROVAL':
        if (now.isBefore(m['approveAt'] as DateTime)) return;
        if (m['payerDeclines'] == true) {
          touch(op, 'FAILED');
          op['failureReason'] = 'Le paiement a été refusé sur le téléphone du payeur. Rien n’a été prélevé.';
          db.addNotification(
            'Paiement non validé',
            op['failureReason'] as String,
            kind: 'ERROR',
            linkType: 'operation',
            linkId: op['id'] as String,
          );
        } else {
          deliver(op);
        }
      case 'CONFIRMATION_CODE':
        if (now.isBefore(m['timeoutAt'] as DateTime)) return;
        touch(op, 'EXPIRED');
        op['cancellationReason'] = 'Le code de confirmation n’a pas été saisi à temps. Rien n’a été prélevé.';
    }
  }

  Map<String, dynamic> executionDto(Map<String, dynamic> op, {String? message}) {
    final m = meta[op['id']] ?? const {};
    final q = m['quote'] as Map<String, dynamic>? ?? const {};
    final status = op['status'] as String;
    final completed = status == 'SUCCESS';
    final awaiting = status == 'PENDING' ? m['awaiting'] : null;
    return {
      'success': true,
      'operationId': op['id'],
      'reference': op['reference'],
      'status': status,
      'merchantReference': op['idempotencyKey'],
      'amount': q['amount'] ?? op['amount'],
      'internalFee': q['internalFee'] ?? op['fee'],
      'externalFeeAdvanced': q['externalFeeAdvanced'] ?? 0,
      'externalFeeWithheld': q['externalFeeWithheld'] ?? 0,
      'amountDebited': op['amountDebited'],
      'amountCredited': op['amountCredited'],
      'providerReference': ?m['providerReference'],
      'completed': completed,
      'awaiting': ?awaiting,
      'message':
          message ??
          switch ((status, awaiting)) {
            ('SUCCESS', _) => '${(op['service'] as Map)['label']} effectué avec succès.',
            (_, 'CONFIRMATION_CODE') =>
              'Demande envoyée — le client a reçu un code de confirmation. Saisissez-le pour valider le paiement.',
            (_, 'PAYER_APPROVAL') => 'Demande envoyée — le client doit valider le paiement sur son téléphone.',
            ('CANCELLED', _) => 'Opération déjà traitée : elle a été annulée.',
            _ => 'Opération ${status.toLowerCase()}.',
          },
    };
  }

  // ---------------------------------------------------------------- Portefeuilles externes (Partie 6 §3.1)
  api.on('GET', '/external-wallets/channels', (r) {
    final country = '${r.query['country'] ?? ''}'.toUpperCase();
    final operation = '${r.query['operation'] ?? ''}'.toUpperCase();
    final data = [
      for (final c in _channels)
        if (country.isEmpty || country == 'BJ')
          if (operation != 'PAYOUT' || c.payout)
            if (operation != 'COLLECT' || c.collect) _channelJson(c),
    ];
    return FakeResponse.ok({'success': true, 'data': data, 'count': data.length});
  });

  // ---------------------------------------------------------------- Sorties d'argent par carte (§7, §8)
  FakeResponse? sourceCardRefusal() {
    if (db.cardStatus == 'PreActive') {
      return _rejected(
        'Cette carte n’a pas encore été activée. Rechargez-la une première fois pour pouvoir l’utiliser.',
      );
    }
    return cardStateRefusal(db);
  }

  FakeResponse? amountInvalid(Object? amount) {
    if (amount is! num) {
      return FakeResponse.validation({
        'amount': ['amount must be a number conforming to the specified constraints'],
      });
    }
    if (amount < 100) {
      return FakeResponse.validation({
        'amount': ['amount must not be less than 100'],
      });
    }
    if (amount > 10000000) {
      return FakeResponse.validation({
        'amount': ['amount must not be greater than 10000000'],
      });
    }
    return null;
  }

  /// Réponse d'initiation (`InitTransferResponseDto` / `InitOperationResponseDto`).
  Map<String, dynamic> initDto(Map<String, dynamic> op, {required bool replay, Map<String, dynamic>? target}) {
    final m = meta[op['id']]!;
    final otp = m['otp'] == true && !replay;
    return {
      'success': true,
      'operationId': op['id'],
      'requiresConfirmation': m['otp'] == true,
      'otpChannel': otp ? m['otpChannel'] : null,
      'sentTo': otp ? m['sentTo'] : null,
      'expiresInSeconds': otp ? 300 : 0,
      'attemptsLeft': otp ? 3 : 0,
      'fee': op['fee'],
      'amountDebited': op['amountDebited'],
      'amountCredited': op['amountCredited'],
      'cardHolderName': db.holderName,
      'isReplay': replay,
      if (target != null) ...{'targetLast4': target['last4'], 'targetHolderName': target['name']},
    };
  }

  Map<String, dynamic> newCardOp({
    required String kind,
    required num amount,
    required num fee,
    required String? requestId,
    required String otpChannel,
    List<Map<String, dynamic>> extraCards = const [],
    List<Map<String, dynamic>> parties = const [],
    Map<String, dynamic> extra = const {},
  }) {
    final otp = !db.hasPin;
    final op = db.newOperation(
      type: kind == 'transfer' ? 'CARD_OPERATION' : 'WALLET_OPERATION',
      status: otp ? 'PENDING_APPROVAL' : 'PENDING',
      serviceSlug: kind == 'transfer' ? 'merchant:card:transfer' : 'merchant:card:card-to-wallet',
      serviceLabel: kind == 'transfer' ? 'Transfert carte à carte' : 'Retrait vers un portefeuille mobile',
      amount: amount,
      fee: fee,
      cardRole: 'SOURCE',
      extraCards: extraCards,
      parties: parties,
      idempotencyKey: requestId,
    );
    db.operations.insert(0, op);
    final channel = otpChannel == 'WHATSAPP' && db.channels['WHATSAPP'] != true ? 'SMS' : otpChannel;
    meta[op['id'] as String] = {
      'kind': kind,
      'otp': otp,
      'otpChannel': channel,
      'sentTo': channel == 'EMAIL' ? db.maskedEmail : '********${'${db.holder['phone']}'.substring(7)}',
      'otpExpiresAt': db.now().add(const Duration(minutes: 5)),
      'otpAttempts': 3,
      ...extra,
    };
    if (requestId != null) db.idempotency['card:$requestId'] = op['id'] as String;
    return op;
  }

  api.on(
    'POST',
    '/cards/transfer/initiate',
    (r) {
      final b = r.body;
      final from = b['fromCardCustomerId'], to = b['toCardCustomerId'];
      final errors = <String, List<String>>{
        if (from is! String) 'fromCardCustomerId': ['fromCardCustomerId must be a string'],
        if (to is! String) 'toCardCustomerId': ['toCardCustomerId must be a string'],
      };
      if (errors.isNotEmpty) return FakeResponse.validation(errors);
      final bad = amountInvalid(b['amount']);
      if (bad != null) return bad;
      if (from == to) return _rejected('La carte de destination doit être différente de la carte de départ.');
      if (from != db.sessionCardId) {
        return FakeResponse.error(
          403,
          'FORBIDDEN',
          'Vous ne pouvez agir que sur la carte avec laquelle vous vous êtes connecté. Reconnectez-vous avec l’autre carte pour l’utiliser.',
        );
      }
      final target = _directory[(to as String).replaceAll(' ', '')];
      if (target == null) {
        return FakeResponse.error(404, 'NOT_FOUND', 'Aucune carte ne correspond à l’identifiant $to.');
      }
      if (target['status'] == 'IA') {
        return _rejected(
          'Cette carte est suspendue. Réactivez-la d’abord : tant qu’elle est suspendue, aucune autre opération n’est possible.',
        );
      }
      final amount = b['amount'] as num;
      final fee = _transferFee(amount);
      final refused = sourceCardRefusal();
      if (refused != null) return refused;
      if (db.balance < amount + fee) return _insufficient(db.balance, amount + fee);
      final requestId = b['requestId'] as String?;
      final existing = requestId == null ? null : db.operationById(db.idempotency['card:$requestId'] ?? '');
      if (existing != null) return FakeResponse.ok(initDto(existing, replay: true, target: target));
      final op = newCardOp(
        kind: 'transfer',
        amount: amount,
        fee: fee,
        requestId: requestId,
        otpChannel: '${b['otpChannel'] ?? 'SMS'}',
        extraCards: [
          {
            'id': db.id('cloc'),
            'cardCustomerId': to,
            'cardLast4': target['last4'],
            'firstName': (target['name'] as String).split(' ').first,
            'lastName': (target['name'] as String).split(' ').skip(1).join(' '),
            'holderName': target['name'],
            'role': 'TARGET',
            'isExternal': false,
            'internalCardId': null,
            'cardTier': null,
            'createdAt': db.iso(db.now()),
          },
        ],
        extra: {'targetName': target['name']},
      );
      return FakeResponse.ok(initDto(op, replay: false, target: target));
    },
    fields: {
      'fromCardCustomerId',
      'toCardCustomerId',
      'cardTierSlug',
      'toCardTierSlug',
      'amount',
      'otpChannel',
      'requestId',
    },
  );

  api.on(
    'POST',
    '/cards/to-mobile-money/initiate',
    (r) {
      final b = r.body;
      final errors = <String, List<String>>{
        if (b['phone'] is! String || (b['phone'] as String).trim().isEmpty) 'phone': ['phone must be a string'],
        if (b['wallet'] is! String || (b['wallet'] as String).trim().isEmpty) 'wallet': ['wallet must be a string'],
        for (final k in ['firstName', 'lastName'])
          if (b[k] is String && (b[k] as String).length > 80) k: ['$k must be shorter than or equal to 80 characters'],
      };
      if (errors.isNotEmpty) return FakeResponse.validation(errors);
      final bad = amountInvalid(b['amount']);
      if (bad != null) return bad;
      final notMine = assertSessionCard(db, b['cardCustomerId'] as String?);
      if (notMine != null) return notMine;
      final channel = _channelBySlug(b['wallet'] as String);
      if (channel == null || !channel.payout) {
        return _rejected(
          'Ce portefeuille ne peut pas recevoir de versement pour le moment. Choisissez un canal de la liste des portefeuilles.',
        );
      }
      final phone = (b['phone'] as String).replaceAll(RegExp(r'[\s-]'), '');
      var name = [b['firstName'], b['lastName']].whereType<String>().map((s) => s.trim()).join(' ').trim();
      var verified = false;
      if (channel.bmo) {
        if (phone.endsWith('0000')) {
          return _rejected(
            'Ce numéro n’a pas de compte BestCash Money : nous ne versons qu’à un compte existant. Vérifiez le numéro.',
          );
        }
        name = _bmoHolder(phone);
        verified = true;
      } else if ('${b['firstName'] ?? ''}'.trim().isEmpty || '${b['lastName'] ?? ''}'.trim().isEmpty) {
        return _rejected('Le prénom et le nom du bénéficiaire sont requis pour ce portefeuille.');
      }
      final amount = b['amount'] as num;
      final fee = _payoutFee(amount);
      final refused = sourceCardRefusal();
      if (refused != null) return refused;
      if (db.balance < amount + fee) return _insufficient(db.balance, amount + fee);
      final requestId = b['requestId'] as String?;
      final existing = requestId == null ? null : db.operationById(db.idempotency['card:$requestId'] ?? '');
      if (existing != null) return FakeResponse.ok(initDto(existing, replay: true));
      final op = newCardOp(
        kind: 'payout',
        amount: amount,
        fee: fee,
        requestId: requestId,
        otpChannel: '${b['otpChannel'] ?? 'SMS'}',
        parties: [
          {
            'role': 'BENEFICIARY',
            'name': name,
            'identifier': _maskPhone(phone),
            'channelSlug': channel.slug,
            'channelLabel': channel.label,
            'verified': verified,
          },
        ],
        extra: {'channelLabel': channel.label, 'reason': b['reason'] ?? 'Retrait depuis carte'},
      );
      return FakeResponse.ok(initDto(op, replay: false));
    },
    fields: {
      'cardCustomerId',
      'cardTierSlug',
      'amount',
      'phone',
      'wallet',
      'firstName',
      'lastName',
      'reason',
      'otpChannel',
      'requestId',
    },
  );

  /// Refus d'état d'une opération carte à conclure (§9).
  FakeResponse? opStateRefusal(Map<String, dynamic> op, String expected) {
    final status = op['status'] as String;
    if (status == expected) return null;
    return _rejected(switch (status) {
      'SUCCESS' => 'Cette opération a déjà été effectuée.',
      'PROCESSING' => 'Cette opération est en cours de traitement.',
      'CANCELLED' => 'Cette opération a été annulée.',
      'EXPIRED' => 'Cette opération a expiré. Recommencez-la.',
      'FAILED' => 'Cette opération a échoué. Recommencez-la.',
      _ => 'Cette opération n’est pas confirmable (état $status).',
    });
  }

  /// Exécution saga d'un débit carte (§9 étape 7).
  FakeResponse runCardOp(Map<String, dynamic> op) {
    final m = meta[op['id']]!;
    final id = op['id'] as String;
    final amount = op['amount'] as num, fee = op['fee'] as num, debited = op['amountDebited'] as num;
    final transfer = m['kind'] == 'transfer';
    if (db.balance < debited) {
      touch(op, 'FAILED');
      op['failureReason'] = 'Solde insuffisant au moment de l’exécution. Votre carte n’a pas été débitée.';
      return FakeResponse.error(
        500,
        'INTERNAL_ERROR',
        '${transfer ? 'Le transfert' : 'Le retrait vers mobile money'} a échoué : solde insuffisant. Votre carte n’a pas été débitée.',
      );
    }
    if (amount == 99999) {
      touch(op, 'FAILED');
      op['failureReason'] =
          'Le sort de cette opération n’a pas pu être déterminé : elle est en vérification par nos équipes.';
      return FakeResponse.error(
        500,
        'INTERNAL_ERROR',
        'Le versement n’a pas pu être confirmé auprès de l’opérateur. L’opération part en vérification : NE LA RELANCEZ PAS, vous risqueriez de payer deux fois.',
      );
    }
    db.balance -= debited;
    db.addIssuerTransaction(transfer ? 'Transfert sortant' : 'Retrait vers ${m['channelLabel']}', -amount, fee: fee);
    addMovement(
      id,
      debited,
      'DEBIT',
      transfer ? 'Transfert vers ${m['targetName']}' : 'Retrait vers ${m['channelLabel']}',
    );
    touch(op, 'SUCCESS');
    db.addNotification(
      transfer ? 'Envoi effectué' : 'Retrait effectué',
      transfer ? '${_fcfa(amount)} envoyés à ${m['targetName']}.' : '${_fcfa(amount)} versés sur ${m['channelLabel']}.',
      kind: 'FINANCIAL',
      linkType: 'operation',
      linkId: id,
    );
    return FakeResponse.ok({
      'success': true,
      'operationId': id,
      'status': 'SUCCESS',
      'fee': fee,
      'amountDebited': debited,
      'amountCredited': op['amountCredited'],
      'reference': id,
      'completedAt': db.iso(db.now()),
      'details': transfer
          ? {'sourceReference': '2089709140', 'targetReference': '2089709141'}
          : {'providerReference': 'BCP-TXN-${db.id('', 6).toUpperCase()}', 'payoutReference': db.id('po_', 8)},
    });
  }

  api.on('POST', '/cards/operations/:id/execute', (r) {
    final pin = r.body['pin'];
    if (pin != null && (pin is! String || !RegExp(r'^\d{6}$').hasMatch(pin))) {
      return FakeResponse.validation({
        'pin': ['Six chiffres attendus.'],
      });
    }
    final op = db.operationById(r.pathParams['id']!);
    if (op == null || meta[op['id']]?['kind'] == null) {
      return FakeResponse.error(404, 'NOT_FOUND', 'Opération introuvable.');
    }
    final refused = opStateRefusal(op, 'PENDING');
    if (refused != null) return refused;
    if (pin == null) {
      return FakeResponse.error(
        400,
        'CARD_CONSENT_REQUIRED',
        'Votre code secret est requis pour payer avec votre carte.',
      );
    }
    final wrong = verifyPin(pin as String);
    if (wrong != null) return wrong;
    touch(op, 'PROCESSING');
    return runCardOp(op);
  }, fields: {'pin'});

  api.on('POST', '/cards/operations/confirm', (r) {
    final b = r.body;
    final code = b['code'];
    final errors = <String, List<String>>{
      if (b['operationId'] is! String) 'operationId': ['operationId must be a string'],
      if (code is! String || !RegExp(r'^\d{6}$').hasMatch(code)) 'code': ['Le code comporte six chiffres.'],
    };
    if (errors.isNotEmpty) return FakeResponse.validation(errors);
    final op = db.operationById(b['operationId'] as String);
    final m = op == null ? null : meta[op['id']];
    if (op == null || m?['kind'] == null) return FakeResponse.error(404, 'NOT_FOUND', 'Opération introuvable.');
    final refused = opStateRefusal(op, 'PENDING_APPROVAL');
    if (refused != null) return refused;
    if (!db.now().isBefore(m!['otpExpiresAt'] as DateTime)) {
      return _rejected('Le code a expiré. Recommencez l’opération pour en recevoir un nouveau.');
    }
    if (code == '000000') {
      final left = (m['otpAttempts'] as int) - 1;
      m['otpAttempts'] = left;
      if (left <= 0) {
        touch(op, 'CANCELLED');
        op['cancellationReason'] = 'Code incorrect : opération annulée par sécurité.';
        return _rejected('Code incorrect. L’opération a été annulée par sécurité.');
      }
      return _rejected('Code incorrect — $left tentative(s) restante(s).');
    }
    touch(op, 'PROCESSING');
    return runCardOp(op);
  }, fields: {'operationId', 'code'});

  api.on('DELETE', '/cards/operations/:id', (r) {
    final op = db.operationById(r.pathParams['id']!);
    final m = op == null ? null : meta[op['id']];
    if (op == null) return FakeResponse.error(404, 'NOT_FOUND', 'Opération introuvable.');
    if (m?['service'] != null) {
      return FakeResponse.error(
        400,
        'USE_FUNDING_CANCEL',
        'Cette opération s’annule par POST /commerce/operations/{id}/funding/cancel, qui prévient le prestataire de paiement.',
      );
    }
    if (!const {'PENDING', 'PENDING_APPROVAL', 'INITIALIZED'}.contains(op['status'])) {
      return _rejected('Cette opération ne peut plus être annulée : elle est déjà en cours de traitement ou terminée.');
    }
    touch(op, 'CANCELLED');
    final reason = r.body['reason'];
    op['cancellationReason'] = reason is String && reason.isNotEmpty ? reason : 'Annulée par son auteur';
    return FakeResponse.ok({'success': true, 'operationId': op['id'], 'message': 'Opération annulée.'});
  });

  api.on('GET', '/cards/operations/:id', (r) {
    final op = db.operationById(r.pathParams['id']!);
    if (op == null) return FakeResponse.error(404, 'NOT_FOUND', 'Opération introuvable.');
    settle(op);
    return FakeResponse.ok(statusDto(op));
  });

  // ---------------------------------------------------------------- Consultations fournisseur (Partie 5 §3.5)
  api.on('GET', '/catalog/lookup/mobile/:msisdn/products', (r) {
    final msisdn = _normalizeMsisdn(r.pathParams['msisdn']!);
    if (msisdn == null) {
      return _rejected(
        'Numéro invalide. Saisissez-le au format international (+22901XXXXXXXX) ou national à dix chiffres (01XXXXXXXX).',
      );
    }
    final type = '${r.query['type'] ?? 'TOPUP'}'.toUpperCase();
    if (!const {'TOPUP', 'DATA', 'COMBO', 'MOBILE_PIN'}.contains(type)) {
      return _rejected('type : TOPUP, DATA, COMBO ou MOBILE_PIN.');
    }
    if (msisdn.endsWith('0000')) return _providerError();
    return FakeResponse.ok({'success': true, 'data': _products(msisdn, type)});
  });

  api.on('GET', '/catalog/lookup/electricity/:ref/invoices', (r) {
    final ref = r.pathParams['ref']!;
    if (ref.endsWith('0000')) return _providerError();
    return FakeResponse.ok({
      'success': true,
      'data': {
        'referenceAbonne': ref,
        'name': 'KOSSI ADJOVI',
        'invoices': [
          {'amount': 12500, 'month': '09', 'year': '2026', 'reference': 'FAC-2026-09-001'},
          {'amount': 9800, 'month': '08', 'year': '2026', 'reference': 'FAC-2026-08-014'},
        ],
      },
    });
  });

  api.on('GET', '/catalog/lookup/tv/:numCard/current', (r) {
    final num = r.pathParams['numCard']!;
    if (!RegExp(r'^[A-Za-z0-9]{8,20}$').hasMatch(num) || num.endsWith('0000')) return _providerError();
    return FakeResponse.ok({
      'success': true,
      'data': {'numCard': num, 'amount': 5000, 'currency': 'XOF', 'mainOfferLabel': 'ACCESS'},
    });
  });

  api.on('GET', '/catalog/lookup/tv/:numCard/offers', (r) {
    final num = r.pathParams['numCard']!;
    if (!RegExp(r'^[A-Za-z0-9]{8,20}$').hasMatch(num) || num.endsWith('0000')) return _providerError();
    return FakeResponse.ok({
      'success': true,
      'data': {'numCard': num, 'offersList': _tvOffers},
    });
  });

  // ---------------------------------------------------------------- Devis (Partie 5 §3.6, §3.7)
  Map<String, dynamic> quoteBody(Map<String, dynamic> q) => {
    'success': true,
    'quoteId': q['quoteId'],
    'feasible': q['feasible'],
    if (q['reason'] != null) 'reason': q['reason'],
    'amount': q['amount'],
    'internalFee': q['internalFee'],
    'externalFeeAdvanced': q['externalFeeAdvanced'],
    'externalFeeWithheld': q['externalFeeWithheld'],
    'amountDebited': q['amountDebited'],
    'amountCredited': q['amountCredited'],
    'currency': 'xof',
    'checks': q['checks'],
    'warnings': q['warnings'],
    if (q['display'] != null) 'display': q['display'],
    'expiresAt': db.iso(q['expiresAt'] as DateTime),
  };

  api.on('POST', '/catalog/quote', (r) {
    final b = r.body;
    final service = b['service'];
    final funding = b['funding'];
    final input = b['input'];
    final errors = <String, List<String>>{
      if (service is! String || service.isEmpty) 'service': ['service should not be empty'],
      if (funding is! Map) 'funding': ['funding must be an object'],
      if (input is! Map) 'input': ['input must be an object'],
    };
    if (errors.isNotEmpty) return FakeResponse.validation(errors);
    final f = Map<String, dynamic>.from(funding as Map);
    final source = f['source'];
    if (!const {'MERCHANT_WALLET', 'CUSTOMER_CARD', 'CUSTOMER_EXTERNAL_CHANNEL'}.contains(source)) {
      return FakeResponse.validation({
        'funding.source': [
          'source must be one of the following values: MERCHANT_WALLET, CUSTOMER_CARD, CUSTOMER_EXTERNAL_CHANNEL',
        ],
      });
    }
    final fundingErrors = _fundingErrors(f);
    if (fundingErrors.isNotEmpty) return FakeResponse.validation(fundingErrors);
    final inp = Map<String, dynamic>.from(input as Map);
    final contract = _inputContract(service as String, inp);
    if (contract != null) return contract;
    final label = _labels[service];
    if (label == null) {
      if (service == 'card-purchase') {
        return FakeResponse.error(
          403,
          'SERVICE_NOT_SELF_SERVICE',
          'Ce service n’est pas disponible depuis votre application. Rendez-vous chez un marchand.',
        );
      }
      return FakeResponse.error(
        404,
        'NOT_FOUND',
        'Service « $service » inconnu. Disponibles : ${_labels.keys.join(', ')}.',
      );
    }
    if (source == 'MERCHANT_WALLET') {
      return FakeResponse.error(
        403,
        'FUNDS_SOURCE_NOT_ALLOWED',
        'Le compte du marchand ne peut pas être utilisé depuis l’application. Payez avec votre carte ou votre portefeuille mobile.',
      );
    }
    if (!_sources[service]!.contains(source)) {
      return FakeResponse.error(404, 'NOT_FOUND', '« $label » ne peut pas être payé par ce moyen.');
    }
    final now = db.now();
    quoteTimes.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    if (quoteTimes.length >= 60) {
      return FakeResponse.error(
        403,
        'QUOTE_RATE_LIMIT',
        'Trop de demandes en peu de temps. Patientez quelques minutes.',
      );
    }
    quoteTimes.add(now);

    final q = _buildQuote(db, service, f, inp, root: b['amount']);
    q
      ..['quoteId'] = db.id('clq')
      ..['service'] = service
      ..['funding'] = f
      ..['input'] = inp
      ..['status'] = q['feasible'] == true ? 'OPEN' : 'REJECTED'
      ..['requestedAt'] = now
      ..['expiresAt'] = now.add(const Duration(minutes: 10));
    db.quotes[q['quoteId'] as String] = q;
    return FakeResponse.ok(quoteBody(q));
  }, fields: {'service', 'amount', 'funding', 'input'});

  api.on('GET', '/catalog/quote/:id', (r) {
    final q = db.quotes[r.pathParams['id']];
    if (q == null || q['service'] == null) return FakeResponse.error(404, 'NOT_FOUND', 'Devis introuvable.');
    final expired = !db.now().isBefore(q['expiresAt'] as DateTime);
    return FakeResponse.ok({
      ...quoteBody(q),
      'status': q['status'],
      'feasible': q['status'] == 'OPEN' && !expired,
      'reason': q['reason'],
      'isExpired': expired,
    });
  });

  // ---------------------------------------------------------------- Confirmation (Partie 5 §3.8)
  api.on('POST', '/catalog/confirm', (r) {
    final b = r.body;
    final funding = b['funding'];
    final errors = <String, List<String>>{
      if (b['quoteId'] is! String || (b['quoteId'] as String).isEmpty) 'quoteId': ['quoteId should not be empty'],
      if (b['service'] is! String || (b['service'] as String).isEmpty) 'service': ['service should not be empty'],
      if (funding is! Map) 'funding': ['funding must be an object'],
      if (b['pin'] != null && (b['pin'] is! String || !RegExp(r'^\d{6}$').hasMatch(b['pin'] as String)))
        'pin': ['Six chiffres attendus.'],
      if (b['reference'] is String && (b['reference'] as String).length > 64)
        'reference': ['reference must be shorter than or equal to 64 characters'],
    };
    if (errors.isNotEmpty) return FakeResponse.validation(errors);
    final f = Map<String, dynamic>.from(funding as Map);
    final fundingErrors = _fundingErrors(f);
    if (fundingErrors.isNotEmpty) return FakeResponse.validation(fundingErrors);
    final byCard = f['source'] == 'CUSTOMER_CARD';

    // 1. Consentement carte : PIN vérifié AVANT tout autre contrôle.
    if (byCard) {
      if (b['pin'] == null) {
        return FakeResponse.error(
          400,
          'CARD_CONSENT_REQUIRED',
          'Votre code secret est requis pour payer avec votre carte.',
        );
      }
      if (db.isExternalCard) {
        return FakeResponse.error(
          403,
          'CARD_CONSENT_UNAVAILABLE',
          'Le paiement par carte n’est pas disponible pour une carte émise hors de la plateforme. Choisissez un autre moyen de paiement.',
        );
      }
      final wrong = verifyPin(b['pin'] as String);
      if (wrong != null) return wrong;
    }

    // 2. Rejeu par référence.
    final reference = b['reference'] as String?;
    final replayId = reference == null ? null : db.idempotency['catalog:$reference'];
    if (replayId != null) {
      final op = db.operationById(replayId)!;
      settle(op);
      return FakeResponse.ok(executionDto(op, message: _replayMessage(op, meta[op['id']])));
    }

    // 3 à 7. Cohérence avec le devis (le devis reste intact).
    final q = db.quotes[b['quoteId']];
    if (q == null || q['service'] == null) {
      return FakeResponse.error(404, 'NOT_FOUND', 'Devis introuvable. Demandez-en un nouveau.');
    }
    if (q['service'] != b['service']) {
      return FakeResponse.error(400, 'QUOTE_SERVICE_MISMATCH', 'Le service ne correspond pas à celui du devis.');
    }
    final qf = q['funding'] as Map<String, dynamic>;
    if (qf['source'] == 'CUSTOMER_EXTERNAL_CHANNEL') {
      final ext = f['external'] is Map ? Map<String, dynamic>.from(f['external'] as Map) : null;
      final qext = Map<String, dynamic>.from(qf['external'] as Map);
      String digits(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'\D'), '');
      if (ext == null ||
          '${ext['channelSlug']}'.trim().toUpperCase() != '${qext['channelSlug']}'.trim().toUpperCase() ||
          digits(ext['payerIdentifier']) != digits(qext['payerIdentifier'])) {
        return FakeResponse.error(
          400,
          'QUOTE_FUNDING_MISMATCH',
          'Le portefeuille payeur ne correspond pas à celui du devis : même canal et même numéro attendus.',
        );
      }
      final channel = _channelBySlug('${ext['channelSlug']}');
      if (channel != null &&
          !channel.bmo &&
          ('${ext['payerFirstName'] ?? ''}'.trim().isEmpty || '${ext['payerLastName'] ?? ''}'.trim().isEmpty)) {
        return FakeResponse.error(
          400,
          'PARTY_NAME_REQUIRED',
          'Le prénom et le nom du payeur sont requis pour ${channel.label} : l’opérateur les exige.',
        );
      }
    } else {
      final card = f['card'] is Map ? Map<String, dynamic>.from(f['card'] as Map) : null;
      if (card == null) {
        return FakeResponse.error(400, 'CARD_SOURCE_REQUIRED', 'Précisez la carte à débiter (funding.card).');
      }
      final last4 = card['last4'];
      if (last4 != null && last4 != db.last4) {
        return FakeResponse.error(
          400,
          'CARD_MISMATCH',
          'Les quatre derniers chiffres ne correspondent pas à cette carte.',
        );
      }
      final notMine = assertSessionCard(db, card['cardCustomerId'] as String?);
      if (notMine != null) return notMine;
      if (!byCard) {
        return FakeResponse.error(
          403,
          'CARD_CONSENT_REQUIRED',
          'Ce devis se paie par carte : confirmez avec votre code secret.',
        );
      }
    }

    // 8. Consommation du devis.
    switch (q['status']) {
      case 'REJECTED':
        return _rejected(q['reason'] as String);
      case 'CONSUMED':
        return _rejected('Ce devis a déjà servi. Demandez-en un nouveau.');
      case 'EXPIRED':
        return _rejected('Ce devis a expiré. Les prix ont pu changer : demandez-en un nouveau.');
    }
    if (!db.now().isBefore(q['expiresAt'] as DateTime)) {
      q['status'] = 'EXPIRED';
      return _rejected('Ce devis a expiré. Les prix ont pu changer : demandez-en un nouveau.');
    }
    q['status'] = 'CONSUMED';

    // 9. Plafonds journaliers (devis déjà consommé).
    final amount = q['amount'] as num;
    if (db.dailyOperations >= 15) {
      return FakeResponse.error(
        403,
        'DAILY_OPERATION_LIMIT',
        'Vous avez atteint le nombre maximal d’opérations sur 24 heures (15). Réessayez plus tard ou rendez-vous chez un marchand.',
      );
    }
    if (db.dailyAmount + amount > 500000) {
      return FakeResponse.error(
        403,
        'DAILY_AMOUNT_LIMIT',
        'Ce paiement dépasserait votre plafond de 500000 XOF sur 24 heures (déjà utilisé : ${db.dailyAmount} XOF). Réessayez plus tard ou rendez-vous chez un marchand.',
      );
    }

    // 10. Création de l'opération.
    final service = q['service'] as String;
    final ext = byCard ? null : _channelBySlug('${(qf['external'] as Map)['channelSlug']}');
    final op = db.newOperation(
      type: _opType(service),
      status: 'PENDING',
      serviceSlug: _pricedSlug(service, byCard),
      serviceLabel: _labels[service]!,
      amount: amount,
      fee: (q['internalFee'] as num) + (q['externalFeeAdvanced'] as num),
      amountDebited: q['amountDebited'] as num,
      amountCredited: q['amountCredited'] as num,
      cardRole: service == 'wallet-to-card' ? 'TARGET' : 'SOURCE',
      parties: _parties(db, service, q, ext),
      idempotencyKey: reference,
      quoteId: q['quoteId'] as String,
    );
    final id = op['id'] as String;
    db.operations.insert(0, op);
    if (reference != null) db.idempotency['catalog:$reference'] = id;
    db.operationDetails[id] = {
      'quote': {
        'id': q['quoteId'],
        for (final k in [
          'amount',
          'internalFee',
          'externalFeeAdvanced',
          'externalFeeWithheld',
          'amountDebited',
          'amountCredited',
          'checks',
          'warnings',
          'display',
        ])
          k: q[k],
        'requestedAt': db.iso(q['requestedAt'] as DateTime),
        'confirmedAt': db.iso(db.now()),
      },
      'movements': <Map<String, dynamic>>[],
    };
    final m = meta[id] = {'service': service, 'quote': q, 'channelLabel': ext?.label};
    db.dailyOperations += 1;
    db.dailyAmount += amount;

    // 11. Prélèvement.
    if (!byCard) {
      final payer = '${(qf['external'] as Map)['payerIdentifier']}'.replaceAll(RegExp(r'\D'), '');
      if (ext!.bmo) {
        m
          ..['awaiting'] = 'CONFIRMATION_CODE'
          ..['codeAttempts'] = 3
          ..['timeoutAt'] = db.now().add(const Duration(minutes: 15));
      } else {
        m
          ..['awaiting'] = 'PAYER_APPROVAL'
          ..['approveAt'] = db.now().add(const Duration(seconds: 15))
          ..['payerDeclines'] = payer.endsWith('9999');
      }
      return FakeResponse.ok(executionDto(op));
    }
    final debited = q['amountDebited'] as num;
    final cardRefusal = sourceCardRefusal();
    if (cardRefusal != null || db.balance < debited) {
      touch(op, 'FAILED');
      final why = cardRefusal != null ? (cardRefusal.body! as Map)['message'] as String : 'Solde insuffisant.';
      op['failureReason'] = 'Débit de la carte refusé : $why';
      db
        ..dailyOperations -= 1
        ..dailyAmount -= amount;
      return _rejected(op['failureReason'] as String);
    }
    db.balance -= debited;
    db.addIssuerTransaction(_issuerLabel(service, q), -amount, fee: debited - amount);
    addMovement(id, debited, 'DEBIT', '${_labels[service]} — paiement par carte');

    // 12. Exécution du service.
    final inp = q['input'] as Map<String, dynamic>;
    if (service == 'electricity-prepaid' && '${inp['meterNum']}'.endsWith('9999')) {
      db.balance += debited;
      db.addIssuerTransaction('Remboursement ${_labels[service]}', debited);
      addMovement(id, debited, 'CREDIT', 'Restitution — service non rendu');
      touch(op, 'REFUNDED');
      op['failureReason'] = 'Le fournisseur n’a pas délivré le jeton. Vous avez été remboursé.';
      return FakeResponse.error(
        500,
        'INTERNAL_ERROR',
        'Le service n’a pas pu être rendu : le fournisseur n’a pas répondu. Vous avez été remboursé.',
      );
    }
    if ('${inp['beneficiary'] ?? ''}'.endsWith('9999')) {
      touch(op, 'FAILED');
      op['failureReason'] = 'Sort de l’opération indéterminé : vérification en cours par nos équipes.';
      return FakeResponse.error(
        500,
        'INTERNAL_ERROR',
        'Le sort de cette opération n’a pas pu être déterminé. Elle part en vérification : NE LA RELANCEZ PAS, vous risqueriez de payer deux fois.',
      );
    }
    deliver(op);
    return FakeResponse.ok(executionDto(op));
  }, fields: {'quoteId', 'service', 'funding', 'reference', 'pin', 'cardOtp'});

  // ---------------------------------------------------------------- Code B-MO (Partie 5 §3.9, §3.10)
  Map<String, dynamic>? fundingOp(String id) {
    final op = db.operationById(id);
    return op != null && meta[op['id']]?['service'] != null ? op : null;
  }

  api.on('POST', '/commerce/operations/:id/funding/confirm', (r) {
    final code = r.body['code'];
    if (code is! String || !RegExp(r'^\d{4,8}$').hasMatch(code)) {
      return FakeResponse.validation({
        'code': ['Le code se compose de 4 à 8 chiffres.'],
      });
    }
    final op = fundingOp(r.pathParams['id']!);
    if (op == null) return FakeResponse.error(404, 'NOT_FOUND', 'Opération introuvable.');
    settle(op);
    final m = meta[op['id']]!;
    if (op['status'] == 'SUCCESS') return FakeResponse.ok(executionDto(op));
    if (op['status'] != 'PENDING') {
      return FakeResponse.error(
        400,
        'OPERATION_NOT_PENDING',
        'Cette opération n’attend plus rien (état ${op['status']}).',
      );
    }
    if (m['awaiting'] != 'CONFIRMATION_CODE') {
      return FakeResponse.error(
        400,
        'NOT_A_CODE_PAYMENT',
        'Ce paiement se valide sur le téléphone du payeur : aucun code à saisir.',
      );
    }
    if (RegExp(r'^0+$').hasMatch(code)) {
      final left = (m['codeAttempts'] as int) - 1;
      m['codeAttempts'] = left;
      if (left <= 0) {
        touch(op, 'CANCELLED');
        op['cancellationReason'] = 'Trop de codes refusés : le paiement a été annulé. Rien n’a été prélevé.';
        return FakeResponse.error(
          400,
          'CONFIRMATION_ATTEMPTS_EXHAUSTED',
          'Trop de codes refusés : le paiement a été annulé. Rien n’a été prélevé. Demandez un nouveau devis.',
          details: {'attemptsLeft': 0},
        );
      }
      return FakeResponse.error(
        400,
        'INVALID_CONFIRMATION_CODE',
        'Code refusé. $left essai(s) restant(s).',
        details: {'attemptsLeft': left},
      );
    }
    deliver(op);
    return FakeResponse.ok(executionDto(op));
  }, fields: {'code'});

  api.on('POST', '/commerce/operations/:id/funding/cancel', (r) {
    final op = fundingOp(r.pathParams['id']!);
    if (op == null) return FakeResponse.error(404, 'NOT_FOUND', 'Opération introuvable.');
    settle(op);
    if (op['status'] == 'CANCELLED') return FakeResponse.ok(executionDto(op));
    if (op['status'] != 'PENDING') {
      return FakeResponse.error(
        400,
        'OPERATION_NOT_PENDING',
        'Cette opération n’attend plus rien (état ${op['status']}).',
      );
    }
    if (meta[op['id']]!['awaiting'] != 'CONFIRMATION_CODE') {
      return FakeResponse.error(
        400,
        'NOT_A_CODE_PAYMENT',
        'Un paiement à valider sur le téléphone ne s’annule pas : il expire seul s’il n’est pas validé.',
      );
    }
    touch(op, 'CANCELLED');
    op['cancellationReason'] = 'Paiement abandonné par le payeur. Rien n’a été prélevé.';
    db
      ..dailyOperations -= 1
      ..dailyAmount -= op['amount'] as num;
    return FakeResponse.ok(executionDto(op, message: 'Opération déjà traitée : elle a été annulée.'));
  }, fields: const {});
}

// ================================================================== Données et règles

FakeResponse _rejected(String message) => FakeResponse.error(400, 'REQUEST_REJECTED', message);

FakeResponse _providerError() =>
    FakeResponse.error(500, 'INTERNAL_ERROR', 'Une erreur inattendue est survenue. Réessayez dans un instant.');

FakeResponse _insufficient(num available, num needed) =>
    _rejected('Solde insuffisant : $available disponible(s), $needed nécessaire(s) (frais compris).');

String _fcfa(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

/// Cartes connues de l'émetteur (destinataires de transfert).
const _directory = <String, Map<String, String>>{
  '121436999': {'name': 'Afiavi Sossou', 'last4': '9034', 'status': 'AC'},
  '121437000': {'name': 'Koffi Agbodjan', 'last4': '1203', 'status': 'AC'},
  '121436555': {'name': 'Rachidi Bello', 'last4': '7781', 'status': 'IA'},
};

num _transferFee(num a) => a <= 5000
    ? 100
    : a <= 50000
    ? 440
    : a <= 200000
    ? 1100
    : (a * 0.006).round();

num _payoutFee(num a) {
  final f = (a * 0.022).round();
  return f < 100 ? 100 : f;
}

typedef _Channel = ({String slug, String label, bool bmo, bool collect, bool payout, int order});

const _channels = <_Channel>[
  (slug: 'MOMO', label: 'MTN Mobile Money', bmo: false, collect: true, payout: true, order: 100),
  (slug: 'MOOVMONEY', label: 'Moov Money (Flooz)', bmo: false, collect: true, payout: true, order: 110),
  (slug: 'CELTISCASH', label: 'Celtiis Mobile Money', bmo: false, collect: true, payout: true, order: 120),
  (slug: 'BMO', label: 'BestCash Money', bmo: true, collect: true, payout: true, order: 130),
];

_Channel? _channelBySlug(String slug) =>
    _channels.where((c) => c.slug.toUpperCase() == slug.trim().toUpperCase()).firstOrNull;

Map<String, dynamic> _channelJson(_Channel c) {
  final field = {
    'key': 'phone',
    'label': 'Numéro de téléphone',
    'type': 'tel',
    'required': true,
    'sensitive': false,
    'validation': {
      'default': {'pattern': r'^\+\d{8,15}$'},
      'byCountry': {
        'BJ': {
          'pattern': r'^\+22901\d{8}$',
          'example': '+2290167123456',
          'placeholder': '+229 01 67 12 34 56',
          'errorMessage': 'Numéro Bénin invalide (01 suivi de 8 chiffres).',
          'limits': {'min': 500, 'max': 5000000, 'currency': 'XOF'},
        },
      },
    },
  };
  return {
    'id': 'clch_${c.slug.toLowerCase()}',
    'providerSlug': c.slug,
    'type': 'MOBILE_MONEY',
    'name': c.slug,
    'displayName': c.label,
    'logo': null,
    'description': null,
    'identifierKind': 'msisdn',
    'countries': [
      {'iso2': 'BJ', 'name': 'Bénin', 'phoneCode': '+229', 'currency': 'XOF', 'isActive': true},
    ],
    'collectFields': [field],
    'payoutFields': [field],
    'collectFlow': c.bmo ? 'otp_push' : 'otp_push',
    'payoutFlow': 'direct',
    'collectEnabled': c.collect,
    'payoutEnabled': c.payout,
    'sortOrder': c.order,
    'collectApproval': c.bmo ? 'CONFIRMATION_CODE' : 'PAYER_APPROVAL',
    'holderVerification': c.bmo,
  };
}

/// Titulaire B-MO d'un numéro (vérification du bénéficiaire).
String _bmoHolder(String phone) => phone.endsWith('8') ? 'Afi Mensah' : 'Kossi Adjovi';

/// Nom masqué « Prénom I. ».
String _maskedName(String name) {
  final parts = name.split(' ');
  return parts.length < 2 ? name : '${parts.first} ${parts.last[0]}.';
}

/// `+22901****0018`.
String _maskPhone(String phone) {
  final p = phone.replaceAll(RegExp(r'[\s-]'), '');
  if (p.length < 9) return p;
  return '${p.substring(0, p.length - 8)}****${p.substring(p.length - 4)}';
}

/// Normalisation d'un numéro (`+229…`, `229…`, `00229…`, `01XXXXXXXX`). `null` si invalide.
String? _normalizeMsisdn(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^\+\d{8,15}$').hasMatch(s)) return s;
  if (RegExp(r'^00\d{8,15}$').hasMatch(s)) return '+${s.substring(2)}';
  if (RegExp(r'^229\d{8,12}$').hasMatch(s)) return '+$s';
  if (RegExp(r'^01\d{8}$').hasMatch(s)) return '+229$s';
  return null;
}

/// Opérateur déduit du numéro national.
String _operator(String msisdn) {
  final nat = msisdn.startsWith('+229') ? msisdn.substring(4) : msisdn;
  final two = nat.length >= 4 ? nat.substring(2, 4) : '';
  if (two.startsWith('4')) return 'Celtiis';
  const mtn = {'50', '51', '52', '53', '54', '56', '57', '59', '61', '62', '66', '67', '69', '90', '91', '96', '97'};
  return mtn.contains(two) ? 'MTN' : 'Moov';
}

List<Map<String, dynamic>> _products(String msisdn, String type) {
  final op = _operator(msisdn);
  Map<String, dynamic> fixed(String id, String name, num price) => {
    'id': id,
    'name': name,
    'priceType': 'FIXED',
    'price': price,
    'minPrice': price,
    'maxPrice': price,
  };
  return switch (type) {
    'TOPUP' => [
      {'id': '17', 'name': 'Recharge $op', 'priceType': 'RANGE', 'price': null, 'minPrice': 100, 'maxPrice': 30000},
      fixed('21', 'Pass crédit 500 $op', 500),
    ],
    'DATA' => [
      fixed('18472', '166Mo (Self Bundle) - 24Hrs', 100),
      fixed('18480', '1 Go - 7 jours', 1000),
      fixed('18490', '5 Go - 30 jours', 3000),
      fixed('18495', '12 Go - 30 jours', 6000),
    ],
    _ => const [],
  };
}

const _tvOffers = [
  {
    'code': 'ACCESS',
    'label': 'Access',
    'amount': 5000,
    'currency': 'XOF',
    'durationsList': [
      {'code': '1', 'label': '1 mois'},
      {'code': '3', 'label': '3 mois'},
    ],
    'optionsList': <Map<String, dynamic>>[],
  },
  {
    'code': 'EVASION',
    'label': 'Évasion',
    'amount': 10000,
    'currency': 'XOF',
    'durationsList': [
      {'code': '1', 'label': '1 mois'},
      {'code': '3', 'label': '3 mois'},
    ],
    'optionsList': [
      {'code': 'CHR', 'label': 'Charme', 'amount': 3000, 'currency': 'XOF'},
    ],
  },
];

const _labels = <String, String>{
  'mobile-topup': 'Recharge téléphonique',
  'mobile-data': 'Forfait internet',
  'electricity-prepaid': 'Électricité prépayée',
  'electricity-postpaid': 'Facture d’électricité',
  'tv-subscription': 'Abonnement télévision',
  'cash-withdrawal': 'Retrait au guichet',
  'wallet-to-card': 'Recharge de carte depuis un portefeuille mobile',
  'payout-to-external': 'Versement vers un portefeuille externe',
  'external-to-external': 'Transfert entre portefeuilles externes',
  'collect-from-external': 'Encaissement depuis un portefeuille externe',
};

const _both = {'CUSTOMER_CARD', 'CUSTOMER_EXTERNAL_CHANNEL'};
const _sources = <String, Set<String>>{
  'mobile-topup': _both,
  'mobile-data': _both,
  'electricity-prepaid': _both,
  'electricity-postpaid': _both,
  'tv-subscription': _both,
  'cash-withdrawal': _both,
  'wallet-to-card': {'CUSTOMER_EXTERNAL_CHANNEL'},
  'payout-to-external': {'CUSTOMER_CARD'},
  'external-to-external': {'CUSTOMER_EXTERNAL_CHANNEL'},
  'collect-from-external': {'CUSTOMER_EXTERNAL_CHANNEL'},
};

String _opType(String service) => switch (service) {
  'cash-withdrawal' => 'CASH_WITHDRAWAL',
  'wallet-to-card' => 'CARD_OPERATION',
  'payout-to-external' || 'external-to-external' || 'collect-from-external' => 'WALLET_OPERATION',
  _ => 'ADDON_SALE',
};

String _pricedSlug(String service, bool byCard) {
  final suffix = byCard ? 'from-card' : 'from-bcp';
  return switch (service) {
    'mobile-topup' => 'merchant:addon:sell-mno-airtime:$suffix',
    'mobile-data' => 'merchant:addon:sell-mno-data:$suffix',
    'electricity-prepaid' => 'merchant:addon:sell-electricity-prepaid:$suffix',
    'electricity-postpaid' => 'merchant:addon:sell-electricity-postpaid:$suffix',
    'tv-subscription' => 'merchant:addon:sell-tv-subscription:$suffix',
    'cash-withdrawal' => 'merchant:addon:atm:$suffix',
    'wallet-to-card' => 'merchant:card:wallet-to-card',
    'payout-to-external' => 'merchant:external-wallet:payout:from-card',
    'external-to-external' => 'merchant:external-wallet:transfer',
    _ => 'merchant:external-wallet:collect',
  };
}

num _internalFee(String service, num amount) => switch (service) {
  'electricity-prepaid' => 125,
  'electricity-postpaid' => 100,
  'cash-withdrawal' => amount * 0.01 < 100 ? 100 : (amount * 0.01).round(),
  'wallet-to-card' => (amount * 0.01).round(),
  'payout-to-external' => (amount * 0.022).round(),
  _ => 0,
};

Map<String, List<String>> _fundingErrors(Map<String, dynamic> f) {
  final errors = <String, List<String>>{};
  final card = f['card'];
  if (card is Map) {
    if ('${card['cardCustomerId'] ?? ''}'.isEmpty) {
      errors['funding.card.cardCustomerId'] = ['cardCustomerId should not be empty'];
    }
    final last4 = card['last4'];
    if (last4 != null && !RegExp(r'^\d{4}$').hasMatch('$last4')) {
      errors['funding.card.last4'] = ['Quatre chiffres attendus.'];
    }
  }
  final ext = f['external'];
  if (ext is Map) {
    final slug = '${ext['channelSlug'] ?? ''}';
    if (slug.isEmpty || !RegExp(r'^\s*[A-Za-z0-9_-]+\s*$').hasMatch(slug)) {
      errors['funding.external.channelSlug'] = ['channelSlug : lettres, chiffres, « _ » ou « - » uniquement.'];
    }
    if ('${ext['payerIdentifier'] ?? ''}'.trim().isEmpty) {
      errors['funding.external.payerIdentifier'] = ['payerIdentifier should not be empty'];
    }
  }
  final unknown = f.keys.where((k) => !const {'source', 'card', 'external'}.contains(k));
  for (final k in unknown) {
    errors['funding.$k'] = ['property $k should not exist'];
  }
  return errors;
}

/// Contrat `input` par service (Partie 5 §2.2) : 400 `REQUEST_REJECTED`.
FakeResponse? _inputContract(String service, Map<String, dynamic> input) {
  final errs = <String>[];
  void need(String k) {
    if ('${input[k] ?? ''}'.trim().isEmpty) errs.add('input.$k : ce champ est requis.');
  }

  void amount({bool required = false}) {
    final a = input['amount'];
    if (a == null) return;
    if (a is! int) {
      errs.add('input.amount : Montant entier attendu (le franc CFA n’a pas de centimes).');
    } else if (a < 1 || a > 1000000) {
      errs.add('input.amount : entre 1 et 1 000 000.');
    }
  }

  switch (service) {
    case 'mobile-topup':
      need('beneficiary');
      need('productId');
      amount();
    case 'mobile-data':
      need('beneficiary');
      need('productId');
    case 'electricity-prepaid':
      if (!RegExp(r'^\d{6,20}$').hasMatch('${input['meterNum'] ?? ''}')) {
        errs.add('input.meterNum : meterNum : chiffres uniquement.');
      }
      if (!const {'whatsapp', 'email'}.contains(input['recipientChannel'])) {
        errs.add('input.recipientChannel : whatsapp ou email.');
      }
      need('recipientContact');
      amount();
    case 'cash-withdrawal':
      if (!const {'SMS', 'EMAIL', 'WHATSAPP'}.contains(input['deliveryChannel'])) {
        errs.add('input.deliveryChannel : SMS, EMAIL ou WHATSAPP.');
      }
      need('beneficiaryContact');
      final pin = input['pin'];
      if (pin != null && !RegExp(r'^\d{4}$').hasMatch('$pin')) errs.add('input.pin : pin : quatre chiffres.');
      amount();
    case 'wallet-to-card':
      need('cardCustomerId');
      amount();
    case 'tv-subscription':
      if (!RegExp(r'^[A-Za-z0-9]{8,20}$').hasMatch('${input['numCard'] ?? ''}')) {
        errs.add('input.numCard : numCard : lettres et chiffres uniquement.');
      }
    case 'electricity-postpaid':
      need('customerReference');
  }
  if (errs.isEmpty) return null;
  return _rejected('Données invalides pour le service « $service » — ${errs.join(' ; ')}');
}

/// Calcule un devis (`feasible`, montants, `checks`, `warnings`, `display`).
Map<String, dynamic> _buildQuote(
  FakeDb db,
  String service,
  Map<String, dynamic> funding,
  Map<String, dynamic> input, {
  Object? root,
}) {
  final checks = <Map<String, dynamic>>[];
  final warnings = <String>[];
  final display = <String, dynamic>{};
  Map<String, dynamic> refuse(String reason, {String? key, String? label, String? detail}) => {
    'feasible': false,
    'reason': reason,
    'amount': input['amount'] ?? 0,
    'internalFee': 0,
    'externalFeeAdvanced': 0,
    'externalFeeWithheld': 0,
    'amountDebited': 0,
    'amountCredited': 0,
    'checks': [
      ...checks,
      if (key != null) {'key': key, 'label': label ?? key, 'passed': false, 'detail': ?detail},
    ],
    'warnings': warnings,
  };

  // Canal de financement externe (étape 5).
  _Channel? channel;
  if (funding['source'] == 'CUSTOMER_EXTERNAL_CHANNEL') {
    final ext = funding['external'] is Map ? Map<String, dynamic>.from(funding['external'] as Map) : null;
    if (ext == null) {
      return refuse(
        'Précisez le portefeuille du payeur (canal et numéro) : c’est lui qui détermine les frais et la façon dont il validera.',
        key: 'payerAccount',
        label: 'Portefeuille du payeur',
      );
    }
    channel = _channelBySlug('${ext['channelSlug']}');
    if (channel == null || !channel.collect) {
      return refuse(
        'Ce portefeuille n’est pas disponible. Choisissez un canal de la liste des portefeuilles.',
        key: 'payerAccount',
        label: 'Portefeuille du payeur',
      );
    }
    final payer = '${ext['payerIdentifier']}'.replaceAll(RegExp(r'[\s-]'), '');
    if (channel.bmo) {
      if (payer.endsWith('0000')) {
        return refuse(
          'Ce numéro n’a pas de compte ${channel.label} : il n’y a rien à prélever. Vérifiez le numéro.',
          key: 'payerAccount',
          label: 'Portefeuille du payeur',
          detail: 'Aucun compte ${channel.label}',
        );
      }
      display['payerVerifiedName'] = _maskedName(_bmoHolder(payer));
      warnings.add('Vous recevrez un code de ${channel.label} par SMS : saisissez-le pour valider le paiement.');
    } else if ('${ext['payerFirstName'] ?? ''}'.trim().isEmpty || '${ext['payerLastName'] ?? ''}'.trim().isEmpty) {
      return refuse(
        'Le prénom et le nom du payeur sont requis pour ${channel.label} : l’opérateur les exige.',
        key: 'payerAccount',
        label: 'Portefeuille du payeur',
      );
    }
    checks.add({
      'key': 'payerAccount',
      'label': 'Portefeuille du payeur',
      'passed': true,
      'detail': '${channel.label} — ${_maskPhone(payer)}',
    });
    display['fundingApproval'] = channel.bmo ? 'CONFIRMATION_CODE' : 'PAYER_APPROVAL';
  }

  // Vérifications du vendeur (étape 6) et montant (étape 7).
  num? amount = input['amount'] as num? ?? root as num?;
  if (root != null && input['amount'] == null) {
    warnings.add('`amount` à la racine est déprécié pour ce service : placez-le dans `input.amount`.');
  }
  switch (service) {
    case 'mobile-topup' || 'mobile-data':
      final msisdn = _normalizeMsisdn('${input['beneficiary']}');
      if (msisdn == null) {
        return refuse(
          'Numéro invalide. Saisissez-le au format international (+22901XXXXXXXX) ou national à dix chiffres (01XXXXXXXX).',
          key: 'beneficiary',
          label: 'Bénéficiaire',
        );
      }
      if (msisdn.endsWith('0000')) {
        return refuse(
          'L’opérateur ne répond pas pour ce numéro. Vérifiez-le et réessayez.',
          key: 'beneficiary',
          label: 'Bénéficiaire',
          detail: 'Opérateur injoignable',
        );
      }
      final products = _products(msisdn, service == 'mobile-topup' ? 'TOPUP' : 'DATA');
      final product = products.where((p) => p['id'] == '${input['productId']}').firstOrNull;
      if (product == null) {
        return refuse(
          'Ce produit n’est pas disponible sur cette ligne. Choisissez-en un dans la liste.',
          key: 'product',
          label: 'Produit',
        );
      }
      final range = product['priceType'] == 'RANGE';
      if (service == 'mobile-data') {
        if (input['amount'] != null || root != null) {
          warnings.add('Montant ignoré : le prix de ce service est fixé par le fournisseur et appliqué d’office.');
        }
        amount = product['price'] as num;
      } else if (!range) {
        if (amount != null && amount != product['price']) {
          warnings.add('Montant remplacé par le prix du produit : ${product['price']} XOF.');
        }
        amount = product['price'] as num;
      } else {
        final min = product['minPrice'] as num, max = product['maxPrice'] as num;
        if (amount == null) {
          return refuse('Indiquez le montant à envoyer, entre $min et $max XOF.', key: 'amount', label: 'Montant');
        }
        if (amount < min || amount > max) {
          return refuse(
            'Montant hors bornes pour ce produit : entre $min et $max XOF.',
            key: 'amount',
            label: 'Montant',
          );
        }
      }
      checks.add({
        'key': 'beneficiary',
        'label': 'Bénéficiaire',
        'passed': true,
        'detail': '${_operator(msisdn)} · $msisdn',
      });
      display.addAll({
        'productName': product['name'],
        'beneficiary': msisdn,
        'priceType': product['priceType'],
        'price': product['price'],
        'priceRange': range ? {'min': product['minPrice'], 'max': product['maxPrice']} : null,
      });
    case 'electricity-prepaid':
      final contact = '${input['recipientContact']}'.replaceAll(RegExp(r'[\s-]'), '');
      if (input['recipientChannel'] == 'email' && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(contact)) {
        return refuse('Adresse électronique invalide pour l’envoi du jeton.', key: 'recipient', label: 'Coordonnées');
      }
      if (input['recipientChannel'] == 'whatsapp' && !RegExp(r'^\+?\d{8,15}$').hasMatch(contact)) {
        return refuse('Numéro WhatsApp invalide pour l’envoi du jeton.', key: 'recipient', label: 'Coordonnées');
      }
      if (amount == null) {
        return refuse('Indiquez le montant d’électricité à acheter.', key: 'amount', label: 'Montant');
      }
      final meter = '${input['meterNum']}';
      if (meter.endsWith('0000')) {
        return refuse(
          'Ce compteur n’a pas pu être vérifié. Contrôlez le numéro — onze chiffres — et réessayez.',
          key: 'meter',
          label: 'Compteur',
          detail: 'Non reconnu par le fournisseur',
        );
      }
      final kwh = ((amount - 100) / 103.7 * 10).round() / 10;
      checks
        ..add({'key': 'meter', 'label': 'Compteur', 'passed': true, 'detail': '$kwh kWh'})
        ..add({
          'key': 'recipient',
          'label': 'Coordonnées du bénéficiaire',
          'passed': true,
          'detail': input['recipientChannel'] == 'email' ? 'E-mail' : 'WhatsApp',
        });
      display.addAll({
        'customerName': 'ADJOVI KOSSI',
        'meterNum': meter,
        'estimatedKwh': kwh,
        'arrears': 0,
        'serviceFee': 100,
      });
    case 'cash-withdrawal':
      final channelIn = input['deliveryChannel'];
      final contact = '${input['beneficiaryContact']}'.replaceAll(RegExp(r'[\s-]'), '');
      final ok = channelIn == 'EMAIL'
          ? RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(contact)
          : RegExp(r'^\+?\d{8,15}$').hasMatch(contact);
      if (!ok) {
        return refuse(
          channelIn == 'EMAIL'
              ? 'Adresse électronique invalide pour l’envoi du code de retrait.'
              : 'Numéro invalide pour l’envoi du code de retrait.',
          key: 'beneficiaryContact',
          label: 'Bénéficiaire',
        );
      }
      if (amount == null) return refuse('Indiquez le montant de l’opération (input.amount).', key: 'amount');
      final expires = db.now().add(const Duration(minutes: 60));
      final provided = input['pin'] != null;
      warnings.add('Le code de retrait est valable 60 minutes. Non retiré à temps, le montant vous est restitué.');
      if (provided) {
        warnings.add('Le code d’accès n’est pas transmis au bénéficiaire : communiquez-le-lui vous-même.');
      }
      checks.add({
        'key': 'beneficiaryContact',
        'label': 'Bénéficiaire',
        'passed': true,
        'detail': '${channelIn == 'EMAIL' ? 'E-mail' : channelIn} · ${_maskPhone(contact)}',
      });
      display.addAll({
        'beneficiaryContact': channelIn == 'EMAIL' ? contact : _maskPhone(contact),
        'deliveryChannel': channelIn,
        'validityMinutes': 60,
        'expiresAt': db.iso(expires),
        'pinIsProvided': provided,
      });
    case 'wallet-to-card':
      final card = '${input['cardCustomerId']}'.replaceAll(' ', '');
      if (card != db.sessionCardId) {
        return refuse(
          'Vous ne pouvez agir que sur la carte avec laquelle vous vous êtes connecté.',
          key: 'card',
          label: 'Carte',
        );
      }
      if (db.cardStatus == 'LostOrStolen' || db.cardStatus == 'Deactivated' || db.cardStatus == 'Inactive') {
        final refusal = cardStateRefusal(db)!;
        return refuse((refusal.body! as Map)['message'] as String, key: 'card', label: 'Carte');
      }
      if (amount == null) return refuse('Indiquez le montant de l’opération (input.amount).', key: 'amount');
      if (amount > 2000000) {
        return refuse('Dépôt maximal de l’émetteur : 2 000 000 XOF par opération.', key: 'amount', label: 'Montant');
      }
      warnings.add('La carte ne sera créditée qu’après la validation du paiement par le portefeuille.');
      checks.add({'key': 'card', 'label': 'Carte', 'passed': true, 'detail': '•••• ${db.last4}'});
      display.addAll({
        'holderName': db.holderName,
        'cardLast4': db.last4,
        'cardWillReceive': amount,
        'requiresPayerApproval': true,
      });
    case 'tv-subscription':
      if ('${input['numCard']}'.endsWith('0000')) {
        return refuse('Cette carte TV n’a pas pu être vérifiée.', key: 'numCard', label: 'Carte TV');
      }
      final main = input['mainOffer'] as String?;
      if (main != null && input['duration'] == null) {
        return refuse('Choisissez une durée pour ce bouquet avant de poursuivre.', key: 'duration', label: 'Durée');
      }
      final offer = _tvOffers.where((o) => o['code'] == (main ?? 'ACCESS')).firstOrNull;
      if (offer == null) return refuse('Cette combinaison n’est pas disponible.', key: 'offer', label: 'Offre');
      final months = int.tryParse('${input['duration'] ?? 1}') ?? 1;
      amount = (offer['amount']! as num) * months;
      display.addAll({
        'numCard': input['numCard'],
        'offerLabel': offer['label'],
        'amount': amount,
        'currency': 'XOF',
        'isRenewal': main == null,
        if (main != null) ...{'duration': input['duration'], 'options': input['optionsList'] ?? ''},
      });
    case 'electricity-postpaid':
      amount = 22300;
      display.addAll({
        'customerName': 'KOSSI ADJOVI',
        'customerReference': input['customerReference'],
        'invoices': [
          {'reference': 'FAC-2026-09-001', 'amount': 12500, 'period': '09/2026'},
          {'reference': 'FAC-2026-08-014', 'amount': 9800, 'period': '08/2026'},
        ],
        'totalDue': 22300,
        'remainingUnpaid': 0,
      });
    default:
      if (amount == null) return refuse('Indiquez le montant de l’opération (input.amount).', key: 'amount');
  }
  if (amount <= 0) return refuse('Indiquez le montant de l’opération (input.amount).', key: 'amount');

  final internal = _internalFee(service, amount);
  final external = channel == null || channel.bmo ? 0 : (amount * 0.015).round();
  return {
    'feasible': true,
    'amount': amount,
    'internalFee': internal,
    'externalFeeAdvanced': external,
    'externalFeeWithheld': 0,
    'amountDebited': amount + internal + external,
    'amountCredited': amount,
    'checks': checks,
    'warnings': warnings,
    'display': display,
  };
}

List<Map<String, dynamic>> _parties(FakeDb db, String service, Map<String, dynamic> q, _Channel? ext) {
  final input = q['input'] as Map<String, dynamic>;
  final display = q['display'] as Map<String, dynamic>? ?? const {};
  final funding = q['funding'] as Map<String, dynamic>;
  return [
    if (ext != null)
      {
        'role': 'PAYER',
        'name':
            display['payerVerifiedName'] ??
            '${(funding['external'] as Map)['payerFirstName'] ?? ''} ${(funding['external'] as Map)['payerLastName'] ?? ''}'
                .trim(),
        'identifier': _maskPhone('${(funding['external'] as Map)['payerIdentifier']}'),
        'channelSlug': ext.slug,
        'channelLabel': ext.label,
        'verified': ext.bmo,
      },
    if (service == 'mobile-topup' || service == 'mobile-data')
      {
        'role': 'BENEFICIARY',
        'name': null,
        'identifier': _maskPhone('${display['beneficiary']}'),
        'channelSlug': _operator('${display['beneficiary']}').toLowerCase(),
        'channelLabel': '${_operator('${display['beneficiary']}')} Bénin',
        'verified': false,
      },
    if (service == 'electricity-prepaid')
      {
        'role': 'BENEFICIARY',
        'name': display['customerName'],
        'identifier': display['meterNum'],
        'channelSlug': 'sbee',
        'channelLabel': 'SBEE',
        'verified': true,
      },
    if (service == 'cash-withdrawal')
      {
        'role': 'BENEFICIARY',
        'name': input['beneficiaryName'],
        'identifier': display['beneficiaryContact'],
        'channelSlug': 'bmo-atm',
        'channelLabel': 'Retrait au guichet',
        'verified': false,
      },
    if (service == 'tv-subscription')
      {
        'role': 'BENEFICIARY',
        'name': null,
        'identifier': input['numCard'],
        'channelSlug': 'canal-plus',
        'channelLabel': 'Canal+',
        'verified': false,
      },
  ];
}

String _issuerLabel(String service, Map<String, dynamic> q) {
  final display = q['display'] as Map<String, dynamic>? ?? const {};
  return switch (service) {
    'mobile-topup' => 'Paiement Crédit ${_operator('${display['beneficiary']}')}',
    'mobile-data' => 'Paiement Forfait internet ${display['productName']}',
    'electricity-prepaid' => 'SBEE Électricité prépayée',
    'cash-withdrawal' => 'Retrait au guichet',
    'tv-subscription' => 'Canal+ Abonnement',
    _ => _labels[service] ?? service,
  };
}

String _successTitle(String service) => switch (service) {
  'wallet-to-card' => 'Carte rechargée',
  'cash-withdrawal' => 'Code de retrait envoyé',
  'electricity-prepaid' => 'Jeton d’électricité envoyé',
  _ => 'Paiement effectué',
};

String _successMessage(String service, Map<String, dynamic> op, Map<String, dynamic> m) {
  final amount = _fcfa(op['amount'] as num);
  final q = m['quote'] as Map<String, dynamic>;
  final display = q['display'] as Map<String, dynamic>? ?? const {};
  return switch (service) {
    'wallet-to-card' => '$amount crédités sur votre carte depuis ${m['channelLabel']}.',
    'cash-withdrawal' => 'Le code de retrait de $amount a été envoyé au ${display['beneficiaryContact']}.',
    'electricity-prepaid' => 'Le jeton de $amount pour le compteur ${display['meterNum']} a été envoyé.',
    'mobile-data' => '${display['productName']} activé pour ${display['beneficiary']}.',
    'mobile-topup' => '$amount de crédit envoyés au ${display['beneficiary']}.',
    _ => '${_labels[service]} : $amount.',
  };
}

String _replayMessage(Map<String, dynamic> op, Map<String, dynamic>? m) => switch ((op['status'], m?['awaiting'])) {
  ('SUCCESS', _) => 'Opération déjà effectuée — voici son résultat, aucune seconde vente n’a eu lieu.',
  ('PENDING', 'CONFIRMATION_CODE') =>
    'Opération déjà enregistrée : le client a reçu un code, saisissez-le. Ne la relancez pas.',
  ('PENDING' || 'PROCESSING', _) => 'Opération déjà enregistrée et TOUJOURS EN COURS : ne la relancez pas.',
  ('REFUNDED', _) => 'Opération déjà enregistrée : elle a échoué et vous avez été remboursé.',
  ('FAILED', _) => 'Opération déjà enregistrée : elle a échoué.',
  ('CANCELLED', _) => 'Opération déjà enregistrée : elle a été annulée.',
  _ => 'Opération déjà enregistrée : elle a expiré.',
};
