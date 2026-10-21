import 'dart:math';

/// État du faux backend, stocké au format JSON de l'API CardConnect v2 pour que les handlers
/// le renvoient tel quel.
///
/// Valeurs utiles :
/// - connexion : identifiant de carte de 6 à 20 chiffres, 4 chiffres ≠ `0000`, `appId` non vide ;
/// - code reçu (connexion, PIN, OTP d'opération) : tout code à 6 chiffres sauf `000000` ;
/// - PIN existant (si [hasPin]) : `482915`.
class FakeDb {
  FakeDb({
    String cardStatus = 'Active',
    bool hasPin = false,
    this.incident = false,
    this.adsEnabled = true,
    this.persistentSession = false,
    this.onPinChanged,
    bool richHistory = false,
  }) : cardStatus = normalizeCardStatus(cardStatus),
       _pin = hasPin ? '482915' : null {
    _seed();
    if (richHistory) _seedHistory();
  }

  /// Jeu de démo de l'app : un mois d'historique, session et code secret conservés d'un lancement à l'autre.
  factory FakeDb.demo({String? savedPin, void Function(String? pin)? onPinChanged}) =>
      FakeDb(persistentSession: true, onPinChanged: onPinChanged, richHistory: true).._pin = savedPin;

  /// Accepte aussi les anciennes valeurs (`ACTIVE`, `PRE_ACTIVE`…).
  static String normalizeCardStatus(String s) => switch (s.toUpperCase().replaceAll('_', '')) {
    'ACTIVE' => 'Active',
    'INACTIVE' => 'Inactive',
    'PREACTIVE' => 'PreActive',
    'LOSTORSTOLEN' => 'LostOrStolen',
    'DEACTIVATED' => 'Deactivated',
    _ => s,
  };

  final _rnd = Random();
  String id(String prefix, [int len = 10]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return prefix + List.generate(len, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  DateTime now() => DateTime.now();
  DateTime hoursAgo(num h) => now().subtract(Duration(minutes: (h * 60).round()));
  String iso(DateTime d) => d.toUtc().toIso8601String();

  // ---------------- Scénario ----------------
  /// Statut de la carte : `Active` | `Inactive` | `PreActive` | `LostOrStolen` | `Deactivated`.
  String cardStatus;
  bool incident;
  bool adsEnabled;

  /// Canaux de réception du code (`GET /auth/customer/channels`).
  final channels = <String, bool>{'SMS': true, 'WHATSAPP': false, 'EMAIL': true};

  // ---------------- Carte & titulaire ----------------
  String sessionCardId = '121436474';
  String last4 = '4589';
  bool isExternalCard = false;
  final holder = <String, dynamic>{
    'firstName': 'Awa',
    'lastName': 'Houngbédji',
    'email': 'awa.houngbedji@example.com',
    'phoneCode': '+229',
    'phone': '0196666456',
    'country': 'Bénin',
    'city': 'Cotonou',
  };
  String get holderName => '${holder['firstName']} ${holder['lastName']}';
  String get maskedPhone => '+229****456';
  String get maskedEmail => 'aw***@example.com';

  /// Élément de `GET /cards` (`data[0]`).
  Map<String, dynamic> cardJson() => {
    'id': 'clcd_konekt_demo',
    'type': 'VIRTUAL',
    'status': cardStatus,
    'customerId': sessionCardId,
    'last4': last4,
    'cardTierSlug': 'virtual:uba-bj:visa-prepaid-card:6-month',
    'cardTier': {
      'id': 'clct_demo',
      'slug': 'virtual:uba-bj:visa-prepaid-card:6-month',
      'label': 'Virtual Standard - UBA BJ',
      'type': 'VIRTUAL',
      'provider': {'id': 'clcp_demo', 'slug': 'uba-bj:visa-prepaid-card', 'label': 'UBA BJ - VISA PREPAID CARD'},
      'duration': {'value': 6, 'unit': 'MONTH'},
    },
    'holder': {
      'kycId': 'clkyc_demo',
      ...holder,
      'identityStatus': 'APPROVED',
      'identityExpiresAt': '2029-03-14T00:00:00.000Z',
    },
    'merchantId': 'clm_demo',
    'createdAt': '2026-08-12T14:30:52.000Z',
    'updatedAt': '2026-08-14T09:12:03.000Z',
  };

  /// Vocabulaire émetteur (`GET /cards/details`).
  String get issuerStatus => switch (cardStatus) {
    'Active' => 'AC',
    'PreActive' => 'PA',
    'Inactive' => 'IA',
    'LostOrStolen' => 'LC',
    _ => 'DE',
  };

  num balance = 152400;
  num dailyAmount = 0;
  int dailyOperations = 0;

  // ---------------- Auth ----------------
  /// cardCustomerId → `{expiresAt, attemptsLeft, channels}` (code de connexion).
  final loginCodes = <String, Map<String, dynamic>>{};
  int loginCodesThisHour = 0;
  final _sessionTokens = <String>{};
  final _refreshTokens = <String>{};
  final _revoked = <String>{};
  bool _allRevoked = false;

  /// En démo, un jeton émis lors d'un lancement précédent reste valide : l'état en mémoire
  /// est perdu au redémarrage, pas la session stockée sur le téléphone.
  final bool persistentSession;

  bool isValidSessionToken(String? t) =>
      t != null &&
      !_revoked.contains(t) &&
      (_sessionTokens.contains(t) || (persistentSession && !_allRevoked && t.startsWith('st_')));

  /// Rotation du refresh token (usage unique). Faux s'il est inconnu, révoqué ou rejoué.
  bool consumeRefreshToken(String t) {
    if (_refreshTokens.remove(t)) return true;
    return persistentSession && !_allRevoked && t.startsWith('rt_') && _revoked.add(t);
  }

  ({String session, String refresh, String sessionId}) issueTokens() {
    final s = 'st_${id('', 24)}', r = 'rt_${id('', 24)}';
    _sessionTokens.add(s);
    _refreshTokens.add(r);
    return (session: s, refresh: r, sessionId: id('clcs'));
  }

  void revokeSessionToken(String? t) {
    if (t == null) return;
    _sessionTokens.remove(t);
    _revoked.add(t);
  }

  void revokeAll() {
    _sessionTokens.clear();
    _refreshTokens.clear();
    _allRevoked = true;
  }

  // ---------------- PIN ----------------
  String? _pin;
  final void Function(String? pin)? onPinChanged;

  String? get pin => _pin;
  set pin(String? value) {
    _pin = value;
    onPinChanged?.call(value);
  }

  bool get hasPin => pin != null;
  int pinAttemptsLeft = 5;
  DateTime? pinLockedUntil;

  /// Code de vérification PIN en cours (`setup` | `reset`) : `{purpose, expiresAt, attemptsLeft, used}`.
  Map<String, dynamic>? pinCode;

  // ---------------- Historique ----------------
  /// Relevé émetteur (`GET /cards/transactions/:id`), du plus récent au plus ancien, format émetteur brut.
  final issuerTransactions = <Map<String, dynamic>>[];

  /// Opérations plateforme (`GET /operations`), format `OperationListItem`, du plus récent au plus ancien.
  final operations = <Map<String, dynamic>>[];

  /// Détails réservés au détail d'opération (`quote`, `movements`) : operationId → données.
  final operationDetails = <String, Map<String, dynamic>>{};

  /// Devis catalogue / opérations carte en attente (état libre des handlers paiement).
  final quotes = <String, Map<String, dynamic>>{};

  /// Références d'idempotence (`reference` / `requestId`) → operationId.
  final idempotency = <String, String>{};

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  /// Ajoute un mouvement émetteur en tête du relevé. [signedAmount] < 0 = débit.
  /// Le relevé émetteur ne porte PAS de signe : l'app le déduit de `runningBalance`.
  void addIssuerTransaction(String desc, num signedAmount, {num fee = 0, DateTime? at, num? runningBalance}) =>
      issuerTransactions.insert(
        0,
        issuerTransaction(desc, signedAmount, fee: fee, at: at, runningBalance: runningBalance),
      );

  /// Mouvement au format émetteur brut (dates `17-AUG-2026`, heures 12 h et 24 h).
  Map<String, dynamic> issuerTransaction(
    String desc,
    num signedAmount, {
    num fee = 0,
    DateTime? at,
    num? runningBalance,
  }) {
    final d = (at ?? now()).toLocal();
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    String two(int v) => v.toString().padLeft(2, '0');
    return {
      'transactionId': 2089700000 + _rnd.nextInt(99999),
      'transactionDate': '${two(d.day)}-${_months[d.month - 1]}-${d.year}',
      'transactionTime': '${two(h12)}:${two(d.minute)}:${two(d.second)}',
      'transactionTimeHH24': '${two(d.hour)}:${two(d.minute)}:${two(d.second)}',
      'baseAmount': signedAmount.abs(),
      'fee': fee,
      'totalAmount': signedAmount.abs() + (signedAmount < 0 ? fee : 0),
      'runningBalance': runningBalance ?? balance,
      'transactionDesc': desc,
      'referenceInformation': 'REF-${1000 + _rnd.nextInt(8999)}',
      'merchantCountry': 'BJ',
      'extendedInformation': null,
    };
  }

  /// Élément `OperationListItem` (guide Partie 6 §1.1) pour la carte de session.
  Map<String, dynamic> newOperation({
    required String type,
    required String status,
    required String serviceSlug,
    required String serviceLabel,
    required num amount,
    num fee = 0,
    num? amountDebited,
    num? amountCredited,
    String cardRole = 'MAIN',
    List<Map<String, dynamic>> extraCards = const [],
    List<Map<String, dynamic>> parties = const [],
    String? idempotencyKey,
    String? quoteId,
    String? failureReason,
    String? cancellationReason,
    DateTime? at,
  }) {
    final created = at ?? now();
    final prefix = switch (type) {
      'WALLET_OPERATION' => 'WOP',
      'ADDON_SALE' => 'ADS',
      'CASH_WITHDRAWAL' => 'CWD',
      _ => 'COP',
    };
    String two(int v) => v.toString().padLeft(2, '0');
    final u = created.toUtc();
    return {
      'id': id('clop'),
      'type': type,
      'status': status,
      'reference':
          '$prefix-${u.year}${two(u.month)}${two(u.day)}-${two(u.hour)}${two(u.minute)}${two(u.second)}-${id('', 4).toUpperCase()}',
      'idempotencyKey': idempotencyKey,
      'amount': amount,
      'currencyIsoCode': 'xof',
      'fee': fee,
      'amountDebited': amountDebited ?? amount + fee,
      'amountCredited': amountCredited ?? amount,
      'initiationMode': 'CUSTOMER_SELF_SERVICE',
      'origin': 'V2',
      'cards': [
        {
          'id': id('cloc'),
          'cardCustomerId': sessionCardId,
          'cardLast4': last4,
          'firstName': holder['firstName'],
          'lastName': holder['lastName'],
          'holderName': holderName,
          'role': cardRole,
          'isExternal': isExternalCard,
          'internalCardId': 'clcd_konekt_demo',
          'cardTier': {
            'slug': 'virtual:uba-bj:visa-prepaid-card:6-month',
            'label': 'Virtual Standard - UBA BJ',
            'type': 'VIRTUAL',
          },
          'createdAt': iso(created),
        },
        ...extraCards,
      ],
      'parties': parties,
      'serviceId': id('clsrv'),
      'service': {'id': id('clsrv'), 'label': serviceLabel, 'slug': serviceSlug},
      'feeId': fee > 0 ? id('clf') : null,
      'quoteId': quoteId,
      'failureReason': failureReason,
      'cancellationReason': cancellationReason,
      'createdAt': iso(created),
      'updatedAt': iso(created),
      'approvedAt': status == 'SUCCESS' ? iso(created) : null,
    };
  }

  Map<String, dynamic>? operationById(String id) => operations.where((o) => o['id'] == id).firstOrNull;

  // ---------------- Notifications, appareils, préférences ----------------
  /// Modèle `Notification` brut (Partie 6 §2), du plus récent au plus ancien.
  final notifications = <Map<String, dynamic>>[];
  final devices = <Map<String, dynamic>>[];
  String? preferredChannel = 'SMS'; // SMS | EMAIL | WHATSAPP | null
  String? pushToken;

  void addNotification(
    String title,
    String message, {
    String kind = 'INFO',
    String? linkType,
    String? linkId,
    bool read = false,
    DateTime? at,
  }) {
    final created = at ?? now();
    notifications.insert(0, {
      'id': id('clnot'),
      'recipientByString': 'cid_demo',
      'merchantId': 'clm_demo',
      'title': title,
      'message': message,
      'kind': kind,
      'linkType': linkType,
      'linkId': linkId,
      'data': null,
      'readAt': read ? iso(created) : null,
      'archivedAt': null,
      'createdAt': iso(created),
    });
  }

  // ---------------- Contenu (hors API : voir docs) ----------------
  /// Publicités. ⚠️ Aucune route de promotions n'existe dans l'API CardConnect v2 :
  /// le faux backend sert `GET /promotions` en attendant une décision produit.
  final promotions = <Map<String, dynamic>>[
    {
      'id': 'ad_jumia',
      'placement': 'home',
      'priority': 1,
      'eyebrow': 'OFFRE PARTENAIRE',
      'title': '−10 % sur Jumia avec votre carte',
      'body': "Jusqu'au 31 octobre, code KONEKT10 au paiement.",
      'cta': "Voir l'offre",
      'action': {'type': 'url', 'target': 'https://www.jumia.bj'},
      'theme': 'navy',
    },
    {
      'id': 'ad_data',
      'placement': 'home',
      'priority': 2,
      'eyebrow': 'NOUVEAU',
      'title': '12 Go pour 6 000 FCFA',
      'body': 'Forfait 30 jours, activé en quelques secondes.',
      'cta': 'Acheter',
      'action': {'type': 'service', 'target': 'data'},
      'theme': 'gold',
    },
    {
      'id': 'ad_invite',
      'placement': 'home',
      'priority': 3,
      'eyebrow': 'PARRAINAGE',
      'title': 'Invitez un proche, gagnez 1 000 FCFA',
      'body': 'Crédités dès sa première recharge.',
      'cta': 'Inviter',
      'action': {'type': 'url', 'target': 'https://konekt.app/invite'},
      'theme': 'mint',
    },
    {
      'id': 'ad_elec',
      'placement': 'receipt',
      'priority': 1,
      'eyebrow': 'ASTUCE',
      'title': "Payez l'électricité en 30 secondes",
      'body': '',
      'cta': 'Essayer',
      'action': {'type': 'service', 'target': 'elec'},
      'theme': 'gold',
    },
    {
      'id': 'ad_cash',
      'placement': 'history',
      'priority': 1,
      'eyebrow': 'CE WEEK-END',
      'title': 'Retrait au guichet sans frais',
      'body': '',
      'cta': 'Retirer',
      'action': {'type': 'service', 'target': 'cash'},
      'theme': 'mint',
    },
  ];

  // ---------------- Jeu de données initial ----------------
  void _seed() {
    // Relevé émetteur (du plus ancien au plus récent pour calculer le solde courant).
    final seed = <(String, num, num, double)>[
      ('Paiement Crédit MTN', -2000, 0, 98),
      ('Rechargement depuis MTN MoMo', 100000, 0, 50),
      ('JUMIA BJ Paiement en ligne', -8500, 0, 26),
      ('Transfert sortant', -50000, 440, 3),
    ];
    var running = balance + 50440 + 8500 - 100000 + 2000;
    for (final (desc, amount, fee, h) in seed) {
      running += amount < 0 ? amount - fee : amount;
      addIssuerTransaction(desc, amount, fee: fee, at: hoursAgo(h), runningBalance: running);
    }

    operations.addAll([
      newOperation(
        type: 'CARD_OPERATION',
        status: 'SUCCESS',
        serviceSlug: 'merchant:card:transfer',
        serviceLabel: 'Transfert carte à carte',
        amount: 50000,
        fee: 440,
        cardRole: 'SOURCE',
        extraCards: [
          {
            'id': id('cloc'),
            'cardCustomerId': '121436999',
            'cardLast4': '9034',
            'firstName': 'Afiavi',
            'lastName': 'Sossou',
            'holderName': 'Afiavi Sossou',
            'role': 'TARGET',
            'isExternal': false,
            'internalCardId': null,
            'cardTier': null,
            'createdAt': iso(hoursAgo(3)),
          },
        ],
        at: hoursAgo(3),
      ),
      newOperation(
        type: 'WALLET_OPERATION',
        status: 'FAILED',
        serviceSlug: 'merchant:card:card-to-wallet',
        serviceLabel: 'Retrait vers un portefeuille mobile',
        amount: 15000,
        fee: 330,
        cardRole: 'SOURCE',
        parties: [
          {
            'role': 'BENEFICIARY',
            'name': 'Afi M.',
            'identifier': '+22901****0018',
            'channelSlug': 'moov-benin',
            'channelLabel': 'Moov Money',
            'verified': false,
          },
        ],
        failureReason: "Portefeuille introuvable. Votre carte n'a pas été débitée.",
        at: hoursAgo(30),
      ),
      newOperation(
        type: 'CARD_OPERATION',
        status: 'SUCCESS',
        serviceSlug: 'merchant:card:wallet-to-card',
        serviceLabel: 'Recharge de carte depuis un portefeuille mobile',
        amount: 100000,
        fee: 1000,
        amountDebited: 101000,
        amountCredited: 100000,
        parties: [
          {
            'role': 'PAYER',
            'name': 'Awa H.',
            'identifier': '+22901****0062',
            'channelSlug': 'mtn-benin',
            'channelLabel': 'MTN Mobile Money',
            'verified': true,
          },
        ],
        at: hoursAgo(50),
      ),
    ]);

    addNotification(
      'Nouvelle connexion',
      'Connexion depuis un iPhone à Cotonou.',
      kind: 'SECURITY',
      read: true,
      at: hoursAgo(120),
    );
    addNotification(
      'Retrait échoué',
      "Votre retrait de 15 000 FCFA vers Moov Money n'a pas abouti. Aucun débit.",
      kind: 'ERROR',
      linkType: 'operation',
      linkId: operations[1]['id'] as String,
      at: hoursAgo(30),
    );
    addNotification(
      'Envoi effectué',
      '50 000 FCFA envoyés à Afiavi Sossou.',
      kind: 'FINANCIAL',
      linkType: 'operation',
      linkId: operations[0]['id'] as String,
      at: hoursAgo(3),
    );

    devices.addAll([
      {
        'deviceId': 'cldev_current',
        'type': 'ANDROID',
        'label': 'Cet appareil',
        'isCurrent': true,
        'hasActiveSession': true,
        'notificationsEnabled': false,
        'lastSeenAt': iso(now()),
        'lastIpAddress': '41.85.***.***',
        'firstSeenAt': iso(hoursAgo(400)),
      },
      {
        'deviceId': 'cldev_iphone',
        'type': 'IOS',
        'label': 'iPhone 12',
        'isCurrent': false,
        'hasActiveSession': true,
        'notificationsEnabled': true,
        'lastSeenAt': iso(hoursAgo(120)),
        'lastIpAddress': '41.85.***.***',
        'firstSeenAt': iso(hoursAgo(900)),
      },
      {
        'deviceId': 'cldev_web',
        'type': 'WEB',
        'label': 'Navigateur web',
        'isCurrent': false,
        'hasActiveSession': false,
        'notificationsEnabled': false,
        'lastSeenAt': iso(hoursAgo(400)),
        'lastIpAddress': '102.64.***.***',
        'firstSeenAt': iso(hoursAgo(1200)),
      },
    ]);
  }

  /// Un mois d'activité supplémentaire (pagination de l'historique, démo).
  void _seedHistory() {
    const samples = <(String, num, num)>[
      ('Paiement Crédit MTN', -1000, 0),
      ('Paiement Forfait internet 5 Go', -3000, 0),
      ('SBEE Électricité prépayée', -10000, 125),
      ('Transfert sortant', -20000, 440),
      ('NETFLIX.COM Paiement en ligne', -5200, 0),
      ('Rechargement depuis Moov Money', 50000, 0),
      ('Retrait vers MTN MoMo', -15000, 330),
      ('Retrait au guichet', -10000, 100),
      ('AMAZON Paiement en ligne', -18750, 0),
      ('Rechargement depuis MTN MoMo', 25000, 0),
    ];
    // Mouvements plus anciens, ajoutés en fin de relevé : solde courant reconstitué à rebours.
    var running = issuerTransactions.last['runningBalance'] as num;
    running -= _signedOf(issuerTransactions.last);
    var hours = 110.0;
    for (var i = 0; i < 22; i++) {
      final (desc, amount, fee) = samples[i % samples.length];
      issuerTransactions.add(issuerTransaction(desc, amount, fee: fee, at: hoursAgo(hours), runningBalance: running));
      running -= amount < 0 ? amount - fee : amount;
      hours += 26 + (i * 7) % 19;
    }

    const opSamples = <(String, String, String, num, num, String?, String)>[
      ('CARD_OPERATION', 'merchant:card:transfer', 'Transfert carte à carte', 20000, 440, null, 'SUCCESS'),
      ('ADDON_SALE', 'electricity-prepaid', 'Électricité prépayée', 10000, 125, null, 'SUCCESS'),
      (
        'WALLET_OPERATION',
        'merchant:card:card-to-wallet',
        'Retrait vers un portefeuille mobile',
        15000,
        330,
        null,
        'SUCCESS',
      ),
      (
        'ADDON_SALE',
        'mobile-topup',
        'Recharge téléphonique',
        1000,
        0,
        "L'opérateur n'a pas répondu. Votre carte n'a pas été débitée.",
        'FAILED',
      ),
      (
        'CARD_OPERATION',
        'merchant:card:wallet-to-card',
        'Recharge de carte depuis un portefeuille mobile',
        50000,
        500,
        null,
        'SUCCESS',
      ),
      ('CASH_WITHDRAWAL', 'cash-withdrawal', 'Retrait au guichet', 10000, 100, null, 'SUCCESS'),
      ('ADDON_SALE', 'mobile-data', 'Forfait internet', 3000, 0, null, 'SUCCESS'),
    ];
    hours = 110;
    for (var i = 0; i < 14; i++) {
      final (type, slug, label, amount, fee, failure, status) = opSamples[i % opSamples.length];
      operations.add(
        newOperation(
          type: type,
          status: status,
          serviceSlug: slug,
          serviceLabel: label,
          amount: amount,
          fee: fee,
          cardRole: slug == 'merchant:card:wallet-to-card' ? 'MAIN' : 'SOURCE',
          failureReason: failure,
          at: hoursAgo(hours),
        ),
      );
      hours += 40 + (i * 11) % 23;
    }
  }

  /// Montant signé d'un mouvement du jeu de données (débit si le libellé ne parle pas de recharge).
  num _signedOf(Map<String, dynamic> tx) {
    final desc = '${tx['transactionDesc']}'.toLowerCase();
    final credit = desc.contains('rechargement') || desc.contains('entrant');
    return credit ? tx['baseAmount'] as num : -(tx['totalAmount'] as num);
  }
}
