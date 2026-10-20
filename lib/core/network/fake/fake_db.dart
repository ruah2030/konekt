import 'dart:math';

/// État du faux backend. Les données sont stockées au format JSON du contrat d'API,
/// pour que les handlers les renvoient telles quelles.
///
/// Valeurs de test utiles (reprises de la maquette) :
/// - invitation : tout code de 8 caractères sauf `00000000` ou `XXXX…`
/// - connexion : n'importe quel identifiant de 6 à 20 chiffres, last4 ≠ `0000`
/// - OTP / code de vérification : tout code sauf `000000`
/// - PIN existant (si [hasPin]) : `482915`
class FakeDb {
  FakeDb({this.cardStatus = 'ACTIVE', bool hasPin = false, this.incident = false, this.adsEnabled = true})
    : pin = hasPin ? '482915' : null {
    _seed();
  }

  final _rnd = Random();
  String id(String prefix, [int len = 4]) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
    return prefix + List.generate(len, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  DateTime now() => DateTime.now();
  DateTime hoursAgo(num h) => now().subtract(Duration(minutes: (h * 60).round()));

  // ---------------- Scénario ----------------
  String cardStatus; // ACTIVE | INACTIVE | PRE_ACTIVE | LOST_OR_STOLEN
  bool incident;
  bool adsEnabled;

  // ---------------- Onboarding ----------------
  int waitlistPosition = 213;

  // ---------------- Auth ----------------
  String sessionCardId = '121436474';
  String last4 = '4589';

  /// challengeId → {expiresAt, sends, tries, channel, verified}
  final challenges = <String, Map<String, dynamic>>{};
  final accessTokens = <String>{};
  final refreshTokens = <String>{};
  int otpSendsThisHour = 0;

  bool isValidAccessToken(String? t) => t != null && accessTokens.contains(t);

  ({String access, String refresh}) issueTokens() {
    final a = 'at_${id('', 24)}', r = 'rt_${id('', 24)}';
    accessTokens.add(a);
    refreshTokens.add(r);
    return (access: a, refresh: r);
  }

  void revokeAll() {
    accessTokens.clear();
    refreshTokens.clear();
  }

  // ---------------- PIN ----------------
  String? pin;
  int pinTries = 5;
  DateTime? pinLockedUntil;

  /// Jeton délivré après vérification du code SMS/e-mail (création / réinitialisation du PIN).
  String? pinVerificationToken;

  bool get hasPin => pin != null;

  // ---------------- Titulaire & carte ----------------
  final holder = <String, dynamic>{
    'firstName': 'Awa',
    'lastName': 'Houngbédji',
    'fullName': 'Awa Houngbédji',
    'initials': 'AH',
    'maskedPhone': '+229 •• •• •• 456',
    'email': 'a•••@gmail.com',
  };

  Map<String, dynamic> cardJson() => {
    'id': sessionCardId,
    'last4': last4,
    'status': cardStatus,
    'brand': 'VISA',
    'product': 'Visa Virtual Standard',
    'issuer': 'UBA Bénin',
    'holderName': 'AWA HOUNGBÉDJI',
  };

  int balance = 152400;
  int dailySpent = 0;
  static const dailyLimit = 500000;

  // ---------------- Historique ----------------
  final transactions = <Map<String, dynamic>>[];
  final operations = <Map<String, dynamic>>[];
  final quotes = <String, Map<String, dynamic>>{};

  /// Idempotency-Key → operationId
  final idempotency = <String, String>{};

  // ---------------- Notifications, appareils, préférences ----------------
  final notifications = <Map<String, dynamic>>[];
  final devices = <Map<String, dynamic>>[];
  String? channelPreference = 'SMS'; // SMS | EMAIL | WHATSAPP | null (auto)
  String? pushToken;

  // ---------------- Contenu ----------------
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

  void addNotification(String title, String body, {bool read = false, DateTime? at}) {
    notifications.insert(0, {
      'id': id('ntf_', 6),
      'title': title,
      'body': body,
      'createdAt': (at ?? now()).toIso8601String(),
      'read': read,
    });
  }

  void _seed() {
    transactions.addAll([
      {
        'id': 'tx_1',
        'description': 'Envoi à Afiavi Sossou',
        'kind': 'send',
        'amount': -50440,
        'balanceAfter': 152400,
        'createdAt': hoursAgo(3).toIso8601String(),
      },
      {
        'id': 'tx_2',
        'description': 'JUMIA BJ · Paiement en ligne',
        'kind': 'card',
        'amount': -8500,
        'balanceAfter': 202840,
        'createdAt': hoursAgo(26).toIso8601String(),
      },
      {
        'id': 'tx_3',
        'description': 'Recharge MTN MoMo',
        'kind': 'topup',
        'amount': 100000,
        'balanceAfter': 211340,
        'createdAt': hoursAgo(50).toIso8601String(),
      },
      {
        'id': 'tx_4',
        'description': 'Crédit MTN',
        'kind': 'airtime',
        'amount': -2000,
        'balanceAfter': 111340,
        'createdAt': hoursAgo(98).toIso8601String(),
      },
    ]);
    operations.addAll([
      {
        'id': 'op_7Q2K',
        'service': 'transfer',
        'title': 'Envoyer vers une carte',
        'status': 'SUCCESS',
        'step': 'SUCCESS',
        'amount': 50000,
        'fee': 440,
        'total': 50440,
        'direction': 'DEBIT',
        'beneficiary': 'Afiavi Sossou · •••• 9034',
        'extra': <Map<String, dynamic>>[],
        'createdAt': hoursAgo(3).toIso8601String(),
      },
      {
        'id': 'op_6H1M',
        'service': 'payout',
        'title': 'Retirer vers Mobile Money',
        'status': 'FAILED',
        'step': 'FAILED',
        'amount': 15000,
        'fee': 330,
        'total': 15330,
        'direction': 'DEBIT',
        'beneficiary': 'Moov Money · +229 01 97 •• •• 18',
        'reason': "Portefeuille introuvable. Votre carte n'a pas été débitée.",
        'extra': <Map<String, dynamic>>[],
        'createdAt': hoursAgo(30).toIso8601String(),
      },
      {
        'id': 'op_5D9X',
        'service': 'topup',
        'title': 'Recharger ma carte',
        'status': 'SUCCESS',
        'step': 'SUCCESS',
        'amount': 100000,
        'fee': 1000,
        'total': 101000,
        'direction': 'CREDIT',
        'beneficiary': 'MTN MoMo · +229 01 96 •• •• 62',
        'extra': <Map<String, dynamic>>[],
        'createdAt': hoursAgo(50).toIso8601String(),
      },
    ]);
    addNotification('Nouvelle connexion', 'Connexion depuis un iPhone à Cotonou.', read: true, at: hoursAgo(120));
    addNotification(
      'Retrait échoué',
      "Votre retrait de 15 000 FCFA vers Moov Money n'a pas abouti. Aucun débit.",
      at: hoursAgo(30),
    );
    addNotification('Envoi effectué', '50 000 FCFA envoyés à Afiavi Sossou.', at: hoursAgo(3));
    devices.addAll([
      {
        'id': 'dv_current',
        'label': 'Cet appareil',
        'platform': 'ANDROID',
        'current': true,
        'lastSeenAt': now().toIso8601String(),
      },
      {
        'id': 'dv2',
        'label': 'iPhone 12',
        'platform': 'IOS',
        'current': false,
        'lastSeenAt': hoursAgo(120).toIso8601String(),
      },
      {
        'id': 'dv3',
        'label': 'Navigateur web',
        'platform': 'WEB',
        'current': false,
        'lastSeenAt': hoursAgo(400).toIso8601String(),
      },
    ]);
  }
}
