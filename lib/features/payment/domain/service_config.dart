import '../../../core/domain/service_type.dart';

/// Type de clavier d'un champ de formulaire de service.
enum FieldKind { numeric, tel, text }

/// Champ d'un formulaire de service. [key] = nom du champ dans `POST /v1/quotes`.
class ServiceField {
  const ServiceField(this.key, this.label, this.placeholder, this.kind);
  final String key;
  final String label;
  final String placeholder;
  final FieldKind kind;

  bool get isAmount => key == amountKey;
  static const amountKey = 'amount';
}

/// Choix proposé dans une option radio (opérateur, forfait, canal).
class ServiceOptionItem {
  const ServiceOptionItem({required this.id, required this.label, this.sub, this.price});
  final String id;
  final String label;
  final String? sub;

  /// Prix imposé (forfaits internet).
  final int? price;
}

/// Groupe d'options radio. [apiKey] = champ envoyé dans `POST /v1/quotes`.
/// Si [loadedFromApi], les items viennent de l'API (forfaits internet).
class ServiceOption {
  const ServiceOption({required this.label, required this.apiKey, this.items = const [], this.loadedFromApi = false});
  final String label;
  final String apiKey;
  final List<ServiceOptionItem> items;
  final bool loadedFromApi;
}

/// Configuration d'un formulaire de service (maquette : constante `SV`).
/// Les frais ne sont jamais calculés ici : ils viennent du devis serveur.
class ServiceConfig {
  const ServiceConfig({
    required this.type,
    required this.intro,
    this.fields = const [],
    this.option,
    this.imposedPrice = false,
    this.requiresApproval = false,
  });

  final ServiceType type;
  final String intro;
  final List<ServiceField> fields;
  final ServiceOption? option;

  /// Le montant est fixé par l'option choisie (forfait), pas saisi.
  final bool imposedPrice;

  /// Validation sur le téléphone de l'utilisateur (recharge Mobile Money).
  final bool requiresApproval;

  String get title => type.title;
  bool get hasAmountField => fields.any((f) => f.isAmount);
}

const operatorItems = [
  ServiceOptionItem(id: 'mtn', label: 'MTN MoMo'),
  ServiceOptionItem(id: 'moov', label: 'Moov Money'),
  ServiceOptionItem(id: 'bmo', label: 'BestCash Money'),
  ServiceOptionItem(id: 'celtiis', label: 'Celtiis Cash'),
];

const _amount = ServiceField(ServiceField.amountKey, 'Montant (FCFA)', 'Ex. 25 000', FieldKind.numeric);
const _tel = ServiceField('msisdn', 'Numéro de téléphone', '+229 01 96 66 62 62', FieldKind.tel);

const serviceConfigs = <ServiceType, ServiceConfig>{
  ServiceType.transfer: ServiceConfig(
    type: ServiceType.transfer,
    intro: "Vers n'importe quelle carte Konekt. L'argent arrive immédiatement.",
    fields: [ServiceField('target', 'Carte du bénéficiaire', 'Identifiant de sa carte', FieldKind.numeric), _amount],
  ),
  ServiceType.payout: ServiceConfig(
    type: ServiceType.payout,
    intro: 'Votre carte est débitée et le portefeuille crédité en quelques secondes.',
    option: ServiceOption(label: 'Opérateur', apiKey: 'operator', items: operatorItems),
    fields: [ServiceField('msisdn', 'Numéro du portefeuille', '+229 01 …', FieldKind.tel), _amount],
  ),
  ServiceType.topup: ServiceConfig(
    type: ServiceType.topup,
    intro: 'Depuis votre portefeuille Mobile Money. Vous validerez ensuite sur votre téléphone.',
    option: ServiceOption(label: 'Payer avec', apiKey: 'operator', items: operatorItems),
    fields: [ServiceField('msisdn', 'Numéro du portefeuille à débiter', '+229 01 …', FieldKind.tel), _amount],
    requiresApproval: true,
  ),
  ServiceType.airtime: ServiceConfig(
    type: ServiceType.airtime,
    intro: "Pour vous ou un proche. L'opérateur est détecté à partir du numéro.",
    fields: [_tel, _amount],
  ),
  ServiceType.data: ServiceConfig(
    type: ServiceType.data,
    intro: "Le prix est fixé par l'opérateur.",
    fields: [_tel],
    option: ServiceOption(label: 'Forfait', apiKey: 'planId', loadedFromApi: true),
    imposedPrice: true,
  ),
  ServiceType.elec: ServiceConfig(
    type: ServiceType.elec,
    intro: 'Le code de recharge vous est aussi envoyé par message.',
    fields: [
      ServiceField('meter', 'Numéro du compteur', '11 chiffres', FieldKind.numeric),
      _amount,
      ServiceField('contact', 'Envoyer le code à', 'Numéro WhatsApp ou e-mail', FieldKind.text),
    ],
    option: ServiceOption(
      label: 'Recevoir le code par',
      apiKey: 'deliveryChannel',
      items: [
        ServiceOptionItem(id: 'WHATSAPP', label: 'WhatsApp'),
        ServiceOptionItem(id: 'EMAIL', label: 'E-mail'),
      ],
    ),
  ),
  ServiceType.tv: ServiceConfig(type: ServiceType.tv, intro: ''),
  ServiceType.cash: ServiceConfig(
    type: ServiceType.cash,
    intro: 'Obtenez un code, puis retirez vos espèces chez un point marchand Konekt.',
    fields: [_amount],
  ),
};

ServiceConfig serviceConfig(ServiceType type) => serviceConfigs[type]!;
