import '../../../core/domain/service_type.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/validators.dart';
import 'payment_models.dart';

/// Type de saisie d'un champ de formulaire de service.
enum FieldKind {
  amount,
  cardId,
  tel,
  digits,
  text,
  contact,
  accessCode,
  choice,

  /// Numéro de carte TV : 8 à 20 lettres ou chiffres.
  tvCard,

  /// Référence client (40 caractères au plus).
  reference,
}

/// Origine des choix d'un champ [FieldKind.choice].
enum ChoiceSource { fixed, wallets, products }

/// Condition d'affichage d'un champ.
enum ShowWhen {
  always,

  /// Portefeuille choisi autre que B-MO (prénom et nom exigés).
  walletRequiresNames,

  /// Produits de la ligne chargés (`lookup`).
  productsLoaded,

  /// Produit choisi à montant libre (`RANGE`).
  rangeProduct,
}

/// Choix d'un champ à liste (canal d'envoi, portefeuille, produit).
class ChoiceItem {
  const ChoiceItem({required this.id, required this.label, this.sub, this.price});
  final String id;
  final String label;
  final String? sub;

  /// Prix imposé (forfaits).
  final num? price;
}

/// Champ d'un formulaire de service. [key] = nom du champ envoyé à l'API (et clé de `details`).
class ServiceField {
  const ServiceField(
    this.key,
    this.label,
    this.placeholder,
    this.kind, {
    this.optional = false,
    this.showWhen = ShowWhen.always,
    this.source = ChoiceSource.fixed,
    this.items = const [],
    this.errorKeys = const {},
    this.checkKeys = const {},
    this.hint,
  });

  final String key;
  final String label;
  final String placeholder;
  final FieldKind kind;
  final bool optional;
  final ShowWhen showWhen;
  final ChoiceSource source;
  final List<ChoiceItem> items;

  /// Clés supplémentaires de `details` (`VALIDATION_FAILED`) à afficher sous ce champ.
  final Set<String> errorKeys;

  /// Clés de `checks[]` du devis qui désignent ce champ.
  final Set<String> checkKeys;
  final String? hint;

  bool get isChoice => kind == FieldKind.choice;
}

/// Configuration d'un formulaire de service (maquette : constante `SV`).
/// Les frais ne sont jamais calculés ici : ils viennent du devis serveur.
class ServiceConfig {
  const ServiceConfig({
    required this.type,
    required this.intro,
    required this.path,
    this.fields = const [],
    this.walletOperation,
    this.productType,
    this.comingSoon = false,
  });

  final ServiceType type;
  final String intro;
  final PaymentPath path;
  final List<ServiceField> fields;

  /// `PAYOUT` | `COLLECT` : filtre de `GET /external-wallets/channels`.
  final String? walletOperation;

  /// `TOPUP` | `DATA` : type du lookup des produits de la ligne.
  final String? productType;

  /// Service pas encore proposé dans l'app.
  final bool comingSoon;

  String get title => type.title;
  bool get needsProducts => productType != null;
}

const _amount = ServiceField('amount', 'Montant (FCFA)', 'Ex. 25 000', FieldKind.amount, checkKeys: {'amount'});

const serviceConfigs = <ServiceType, ServiceConfig>{
  ServiceType.transfer: ServiceConfig(
    type: ServiceType.transfer,
    path: PaymentPath.cardOperation,
    intro: "Vers n'importe quelle carte Konekt. L'argent arrive immédiatement.",
    fields: [
      ServiceField('toCardCustomerId', 'Carte du bénéficiaire', 'Identifiant de sa carte', FieldKind.cardId),
      _amount,
    ],
  ),
  ServiceType.payout: ServiceConfig(
    type: ServiceType.payout,
    path: PaymentPath.cardOperation,
    walletOperation: 'PAYOUT',
    intro: 'Votre carte est débitée et le portefeuille crédité en quelques secondes.',
    fields: [
      ServiceField('wallet', 'Portefeuille', '', FieldKind.choice, source: ChoiceSource.wallets),
      ServiceField('phone', 'Numéro du portefeuille', '+229 01 …', FieldKind.tel),
      ServiceField(
        'firstName',
        'Prénom du bénéficiaire',
        'Tel que connu de son opérateur',
        FieldKind.text,
        showWhen: ShowWhen.walletRequiresNames,
      ),
      ServiceField('lastName', 'Nom du bénéficiaire', '', FieldKind.text, showWhen: ShowWhen.walletRequiresNames),
      _amount,
    ],
  ),
  ServiceType.topup: ServiceConfig(
    type: ServiceType.topup,
    path: PaymentPath.catalogExternal,
    walletOperation: 'COLLECT',
    intro: 'Depuis votre portefeuille Mobile Money. Vous validerez ensuite sur votre téléphone.',
    fields: [
      ServiceField(
        'wallet',
        'Payer avec',
        '',
        FieldKind.choice,
        source: ChoiceSource.wallets,
        checkKeys: {'payerAccount'},
      ),
      ServiceField(
        'payerIdentifier',
        'Numéro du portefeuille à débiter',
        '+229 01 …',
        FieldKind.tel,
        errorKeys: {'funding.external.payerIdentifier'},
        checkKeys: {'payerAccount'},
      ),
      ServiceField(
        'payerFirstName',
        'Prénom du titulaire',
        '',
        FieldKind.text,
        showWhen: ShowWhen.walletRequiresNames,
        errorKeys: {'funding.external.payerFirstName'},
      ),
      ServiceField(
        'payerLastName',
        'Nom du titulaire',
        '',
        FieldKind.text,
        showWhen: ShowWhen.walletRequiresNames,
        errorKeys: {'funding.external.payerLastName'},
      ),
      _amount,
    ],
  ),
  ServiceType.airtime: ServiceConfig(
    type: ServiceType.airtime,
    path: PaymentPath.catalogCard,
    productType: 'TOPUP',
    intro: "Pour vous ou un proche. L'opérateur est détecté à partir du numéro.",
    fields: [
      ServiceField(
        'beneficiary',
        'Numéro de téléphone',
        '+229 01 96 66 62 62',
        FieldKind.tel,
        checkKeys: {'beneficiary'},
      ),
      ServiceField(
        'productId',
        'Offre',
        '',
        FieldKind.choice,
        source: ChoiceSource.products,
        showWhen: ShowWhen.productsLoaded,
        checkKeys: {'product'},
      ),
      ServiceField(
        'amount',
        'Montant (FCFA)',
        'Ex. 1 000',
        FieldKind.amount,
        showWhen: ShowWhen.rangeProduct,
        checkKeys: {'amount'},
      ),
    ],
  ),
  ServiceType.data: ServiceConfig(
    type: ServiceType.data,
    path: PaymentPath.catalogCard,
    productType: 'DATA',
    intro: "Le prix est fixé par l'opérateur.",
    fields: [
      ServiceField(
        'beneficiary',
        'Numéro de téléphone',
        '+229 01 96 66 62 62',
        FieldKind.tel,
        checkKeys: {'beneficiary'},
      ),
      ServiceField(
        'productId',
        'Forfait',
        '',
        FieldKind.choice,
        source: ChoiceSource.products,
        showWhen: ShowWhen.productsLoaded,
        checkKeys: {'product'},
      ),
    ],
  ),
  ServiceType.elec: ServiceConfig(
    type: ServiceType.elec,
    path: PaymentPath.catalogCard,
    intro: 'Le code de recharge est envoyé par message au contact de votre choix.',
    fields: [
      ServiceField('meterNum', 'Numéro du compteur', '11 chiffres', FieldKind.digits, checkKeys: {'meter'}),
      _amount,
      ServiceField(
        'recipientChannel',
        'Recevoir le code par',
        '',
        FieldKind.choice,
        items: [
          ChoiceItem(id: 'whatsapp', label: 'WhatsApp'),
          ChoiceItem(id: 'email', label: 'E-mail'),
        ],
      ),
      ServiceField(
        'recipientContact',
        'Envoyer le code à',
        'Numéro WhatsApp ou e-mail',
        FieldKind.contact,
        checkKeys: {'recipient'},
      ),
    ],
  ),
  ServiceType.elecBill: ServiceConfig(
    type: ServiceType.elecBill,
    path: PaymentPath.catalogCard,
    intro: 'Réglez vos factures SBEE impayées. Le montant est celui des factures choisies.',
    fields: [
      ServiceField(
        'customerReference',
        'Référence client SBEE',
        'Ex. 610201551642KA',
        FieldKind.reference,
        checkKeys: {'customerReference'},
      ),
    ],
  ),
  ServiceType.tv: ServiceConfig(
    type: ServiceType.tv,
    path: PaymentPath.catalogCard,
    intro: 'Renouvelez votre abonnement Canal+ ou changez de bouquet. Le prix est fixé par Canal+.',
    fields: [
      ServiceField(
        'numCard',
        'Numéro de carte TV',
        'Ex. 24100027499297',
        FieldKind.tvCard,
        checkKeys: {'numCard'},
        hint: 'Au dos de votre carte Canal+ ou dans le menu de votre décodeur.',
      ),
    ],
  ),
  ServiceType.cash: ServiceConfig(
    type: ServiceType.cash,
    path: PaymentPath.catalogCard,
    intro: 'Un code de retrait est envoyé au bénéficiaire. Il retire les espèces chez un point marchand Konekt.',
    fields: [
      _amount,
      ServiceField(
        'deliveryChannel',
        'Envoyer le code par',
        '',
        FieldKind.choice,
        items: [
          ChoiceItem(id: 'SMS', label: 'SMS'),
          ChoiceItem(id: 'WHATSAPP', label: 'WhatsApp'),
          ChoiceItem(id: 'EMAIL', label: 'E-mail'),
        ],
      ),
      ServiceField(
        'beneficiaryContact',
        'Contact du bénéficiaire',
        'Numéro ou e-mail',
        FieldKind.contact,
        checkKeys: {'beneficiaryContact'},
      ),
      ServiceField(
        'beneficiaryName',
        'Nom du bénéficiaire (facultatif)',
        'Ex. Kossi Adjovi',
        FieldKind.text,
        optional: true,
      ),
      ServiceField(
        'pin',
        "Code d'accès (facultatif)",
        '4 chiffres',
        FieldKind.accessCode,
        optional: true,
        hint: "Si vous le choisissez, il n'est pas envoyé : communiquez-le vous-même au bénéficiaire.",
      ),
    ],
  ),
};

ServiceConfig serviceConfig(ServiceType type) => serviceConfigs[type]!;

/// Choix courants du formulaire (portefeuille et produit résolus).
class FormSelection {
  const FormSelection({this.wallet, this.product, this.productsLoaded = false});
  final WalletChannel? wallet;
  final MobileProduct? product;
  final bool productsLoaded;
}

bool isFieldVisible(ServiceField f, FormSelection s) => switch (f.showWhen) {
  ShowWhen.always => true,
  ShowWhen.walletRequiresNames => s.wallet?.requiresNames ?? false,
  ShowWhen.productsLoaded => s.productsLoaded,
  ShowWhen.rangeProduct => s.product?.isRange ?? false,
};

/// Montant saisi : espaces retirés, virgule → point (`"1 500,5"` → `1500.5`).
num? parseMoney(String input) {
  final v = input.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
  if (v.isEmpty) return null;
  return num.tryParse(v);
}

/// Numéro au format international (`0196…` → `+2290196…`).
String toInternational(String input) {
  final v = input.replaceAll(RegExp(r'[\s\-.]'), '');
  if (v.startsWith('+')) return v;
  if (v.startsWith('00')) return '+${v.substring(2)}';
  if (v.startsWith('229') && v.length >= 11) return '+$v';
  if (RegExp(r'^01\d{8}$').hasMatch(v)) return '+229$v';
  return v;
}

/// Saisie compactée (espaces retirés) : numéro de carte TV, référence client.
String compactCode(String input) => input.replaceAll(RegExp(r'[\s  ]'), '');

/// Numéro de carte TV valide (`numCard` : 8 à 20 lettres ou chiffres).
bool isTvCard(String input) => RegExp(r'^[A-Za-z0-9]{8,20}$').hasMatch(compactCode(input));

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Validations locales (confort). Renvoie les messages par champ ; vide si tout est valide.
Map<String, String> validateForm(
  ServiceConfig config,
  Map<String, String> values,
  FormSelection selection, {
  String? sessionCardId,
}) {
  final errors = <String, String>{};
  final catalog = config.path != PaymentPath.cardOperation;
  for (final f in config.fields) {
    if (!isFieldVisible(f, selection)) continue;
    final v = (values[f.key] ?? '').trim();
    if (v.isEmpty) {
      if (!f.optional) {
        errors[f.key] = f.isChoice ? 'Choisissez : ${f.label.toLowerCase()}.' : '${f.label} : champ obligatoire.';
      }
      continue;
    }
    switch (f.kind) {
      case FieldKind.cardId:
        if (Validators.containsLetterO(v)) {
          errors[f.key] = 'Chiffres uniquement : vérifiez qu’aucune lettre « O » n’a été saisie à la place du zéro.';
        } else if (!Validators.isCardId(v)) {
          errors[f.key] = 'Identifiant de carte invalide : 6 à 20 chiffres.';
        } else if (Validators.digitsOnly(v) == sessionCardId) {
          errors[f.key] = 'La carte de destination doit être différente de la carte de départ.';
        }
      case FieldKind.tel:
        if (!Validators.isMsisdn(v)) errors[f.key] = 'Numéro de téléphone invalide.';
      case FieldKind.digits:
        if (!Validators.isMeter(v)) errors[f.key] = 'Chiffres uniquement (6 à 20).';
      case FieldKind.accessCode:
        if (!RegExp(r'^\d{4}$').hasMatch(v)) errors[f.key] = 'Quatre chiffres.';
      case FieldKind.contact:
        final channel = values['recipientChannel'] ?? values['deliveryChannel'];
        final isEmail = channel?.toLowerCase() == 'email';
        if (isEmail ? !_email.hasMatch(v) : !Validators.isMsisdn(v)) {
          errors[f.key] = isEmail ? 'Adresse e-mail invalide.' : 'Numéro de téléphone invalide.';
        }
      case FieldKind.amount:
        final amount = parseMoney(v);
        final product = selection.product;
        if (amount == null) {
          errors[f.key] = 'Montant invalide.';
        } else if (catalog && amount != amount.roundToDouble()) {
          errors[f.key] = "Montant entier attendu (le franc CFA n'a pas de centimes).";
        } else if (product != null && product.isRange) {
          final min = product.minPrice ?? 1, max = product.maxPrice ?? 1000000;
          if (amount < min || amount > max) {
            errors[f.key] = 'Entre ${formatFcfa(min)} et ${formatFcfa(max)} pour cette offre.';
          }
        } else if (amount < 100) {
          errors[f.key] = 'Montant minimum : ${formatFcfa(100)}.';
        } else if (amount > (catalog ? 1000000 : 10000000)) {
          errors[f.key] = 'Montant maximum : ${formatFcfa(catalog ? 1000000 : 10000000)}.';
        }
      case FieldKind.tvCard:
        if (!isTvCard(v)) errors[f.key] = 'Lettres et chiffres uniquement, 8 à 20 caractères.';
      case FieldKind.reference:
        if (v.length > 40) errors[f.key] = '40 caractères au maximum.';
      case FieldKind.text || FieldKind.choice:
        if (v.length > 80) errors[f.key] = '80 caractères au maximum.';
    }
  }
  if (config.type == ServiceType.tv && (values['mainOffer'] ?? '').trim().isNotEmpty) {
    // Changement de bouquet : la durée est obligatoire (guide Partie 5 §2.2).
    if ((values['duration'] ?? '').trim().isEmpty) errors['duration'] = 'Choisissez une durée pour ce bouquet.';
  }
  return errors;
}

/// Construit la demande envoyée à l'API (formulaire déjà validé).
PaymentRequest buildRequest(
  ServiceConfig config,
  Map<String, String> values,
  FormSelection selection, {
  required String cardCustomerId,
}) {
  String v(String k) => (values[k] ?? '').trim();
  num amount() {
    final a = parseMoney(v('amount'))!;
    return a == a.roundToDouble() ? a.round() : a;
  }

  final card = {
    'source': 'CUSTOMER_CARD',
    'card': {'cardCustomerId': cardCustomerId},
  };
  final wallet = selection.wallet;
  switch (config.type) {
    case ServiceType.transfer:
      return PaymentRequest(
        service: config.type,
        path: config.path,
        cardBody: {
          'fromCardCustomerId': cardCustomerId,
          'toCardCustomerId': Validators.digitsOnly(v('toCardCustomerId')),
          'amount': amount(),
        },
      );
    case ServiceType.payout:
      return PaymentRequest(
        service: config.type,
        path: config.path,
        walletLabel: wallet?.label,
        cardBody: {
          'cardCustomerId': cardCustomerId,
          'amount': amount(),
          'phone': toInternational(v('phone')),
          'wallet': wallet!.slug,
          if (wallet.requiresNames) ...{'firstName': v('firstName'), 'lastName': v('lastName')},
        },
      );
    case ServiceType.topup:
      return PaymentRequest(
        service: config.type,
        path: config.path,
        walletLabel: wallet?.label,
        funding: {
          'source': 'CUSTOMER_EXTERNAL_CHANNEL',
          'external': {
            'channelSlug': wallet!.slug,
            'payerIdentifier': toInternational(v('payerIdentifier')),
            if (wallet.requiresNames) ...{'payerFirstName': v('payerFirstName'), 'payerLastName': v('payerLastName')},
            'countryCode': 'BJ',
          },
        },
        input: {'cardCustomerId': cardCustomerId, 'amount': amount()},
      );
    case ServiceType.airtime || ServiceType.data:
      final product = selection.product!;
      return PaymentRequest(
        service: config.type,
        path: config.path,
        funding: card,
        input: {
          'beneficiary': toInternational(v('beneficiary')),
          'productId': product.id,
          if (config.type == ServiceType.airtime && product.isRange) 'amount': amount(),
        },
      );
    case ServiceType.elec:
      final channel = v('recipientChannel');
      return PaymentRequest(
        service: config.type,
        path: config.path,
        funding: card,
        input: {
          'meterNum': Validators.digitsOnly(v('meterNum')),
          'recipientChannel': channel,
          'recipientContact': channel == 'email' ? v('recipientContact') : toInternational(v('recipientContact')),
          'amount': amount(),
        },
      );
    case ServiceType.cash:
      final channel = v('deliveryChannel');
      final pin = v('pin');
      return PaymentRequest(
        service: config.type,
        path: config.path,
        funding: card,
        accessCode: pin.isEmpty ? null : pin,
        input: {
          'deliveryChannel': channel,
          'beneficiaryContact': channel == 'EMAIL' ? v('beneficiaryContact') : toInternational(v('beneficiaryContact')),
          if (v('beneficiaryName').isNotEmpty) 'beneficiaryName': v('beneficiaryName'),
          if (pin.isNotEmpty) 'pin': pin,
          'amount': amount(),
        },
      );
    case ServiceType.tv:
      // Sans `mainOffer` : reconduction de l'offre en cours ; avec : changement de bouquet (durée obligatoire).
      final main = v('mainOffer');
      return PaymentRequest(
        service: config.type,
        path: config.path,
        funding: card,
        input: {
          'numCard': compactCode(v('numCard')),
          if (main.isNotEmpty) ...{'mainOffer': main, 'duration': v('duration'), 'optionsList': v('optionsList')},
        },
      );
    case ServiceType.elecBill:
      // Sans `invoiceReferences` : toutes les factures impayées sont réglées.
      final refs = v('invoiceReferences').split(',').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();
      return PaymentRequest(
        service: config.type,
        path: config.path,
        funding: card,
        input: {'customerReference': v('customerReference'), if (refs.isNotEmpty) 'invoiceReferences': refs},
      );
  }
}
