import '../../../core/domain/json.dart';
import '../../../core/domain/operation.dart';
import '../../../core/domain/service_type.dart';

/// Contrôle effectué par le serveur au devis (`checks[]`) : `passed:false` désigne le champ à corriger.
class QuoteCheck {
  const QuoteCheck({required this.key, required this.label, required this.passed, this.detail});
  factory QuoteCheck.fromJson(Json j) => QuoteCheck(
    key: j.strOrNull('key') ?? '',
    label: j.strOrNull('label') ?? '',
    passed: j.boolean('passed'),
    detail: j.strOrNull('detail'),
  );
  final String key;
  final String label;
  final bool passed;
  final String? detail;
}

/// Voie de paiement d'un service.
enum PaymentPath {
  /// Catalogue payé par la carte de session (`CUSTOMER_CARD` + PIN).
  catalogCard,

  /// Catalogue payé par un portefeuille mobile (`CUSTOMER_EXTERNAL_CHANNEL`, sans PIN).
  catalogExternal,

  /// Sortie d'argent `/cards/*/initiate` → `execute` (PIN) ou `confirm` (OTP).
  cardOperation,
}

/// Prix annoncé avant confirmation : devis du catalogue (`QuoteResponseDto`) ou opération carte
/// initiée (`InitTransferResponseDto` : frais arrêtés à l'initiation).
class PaymentQuote {
  const PaymentQuote({
    required this.service,
    required this.path,
    required this.amount,
    required this.fee,
    required this.amountDebited,
    required this.amountCredited,
    required this.expiresAt,
    this.feasible = true,
    this.reason,
    this.quoteId,
    this.operationId,
    this.checks = const [],
    this.warnings = const [],
    this.display = const {},
    this.requiresConfirmation = false,
    this.otpChannel,
    this.sentTo,
    this.otpExpiresAt,
    this.targetHolderName,
    this.targetLast4,
    this.beneficiary,
  });

  /// `POST /catalog/quote`.
  factory PaymentQuote.fromCatalog(Json j, {required ServiceType service, required PaymentPath path}) {
    final internal = (j['internalFee'] as num?) ?? 0;
    final advanced = (j['externalFeeAdvanced'] as num?) ?? 0;
    return PaymentQuote(
      service: service,
      path: path,
      quoteId: j.strOrNull('quoteId'),
      feasible: j.boolean('feasible'),
      reason: j.strOrNull('reason'),
      amount: (j['amount'] as num?) ?? 0,
      fee: internal + advanced,
      amountDebited: (j['amountDebited'] as num?) ?? 0,
      amountCredited: (j['amountCredited'] as num?) ?? 0,
      checks: j.list('checks').map(QuoteCheck.fromJson).toList(),
      warnings: j.strings('warnings'),
      display: j['display'] is Map ? j.obj('display') : const {},
      expiresAt: j.date('expiresAt'),
    );
  }

  /// `POST /cards/transfer/initiate` ou `/cards/to-mobile-money/initiate`. L'opération n'expire pas
  /// côté serveur avant exécution : l'app limite elle-même l'offre à [cardOperationValidity].
  factory PaymentQuote.fromCardInit(Json j, {required ServiceType service, required DateTime now}) {
    final otp = j.boolean('requiresConfirmation');
    final expiresIn = j.intOrNull('expiresInSeconds') ?? 0;
    final fee = (j['fee'] as num?) ?? 0;
    final credited = (j['amountCredited'] as num?) ?? 0;
    return PaymentQuote(
      service: service,
      path: PaymentPath.cardOperation,
      operationId: j.str('operationId'),
      amount: credited,
      fee: fee,
      amountDebited: (j['amountDebited'] as num?) ?? credited + fee,
      amountCredited: credited,
      expiresAt: now.add(cardOperationValidity),
      requiresConfirmation: otp,
      otpChannel: j.strOrNull('otpChannel'),
      sentTo: j.strOrNull('sentTo'),
      otpExpiresAt: otp && expiresIn > 0 ? now.add(Duration(seconds: expiresIn)) : null,
      targetHolderName: j.strOrNull('targetHolderName'),
      targetLast4: j.strOrNull('targetLast4'),
    );
  }

  /// Durée pendant laquelle l'app propose de conclure une opération carte initiée (`timeoutAt`).
  static const cardOperationValidity = Duration(minutes: 10);

  /// Marge de sécurité : le PIN est vérifié AVANT le devis côté serveur (Partie 9 #10) ;
  /// au-delà de ~9 min, on redemande un devis plutôt que de risquer un essai de PIN.
  static const safetyMargin = Duration(minutes: 1);

  final ServiceType service;
  final PaymentPath path;
  final String? quoteId;
  final String? operationId;
  final bool feasible;
  final String? reason;
  final num amount;

  /// Frais ajoutés au débit (frais internes + frais du portefeuille avancés).
  final num fee;

  /// Ce que le porteur paie.
  final num amountDebited;

  /// Ce que le bénéficiaire reçoit.
  final num amountCredited;
  final DateTime expiresAt;
  final List<QuoteCheck> checks;
  final List<String> warnings;

  /// Éléments propres au service (`productName`, `customerName`, `holderName`…).
  final Json display;

  /// Voie OTP (porteur sans PIN) : code envoyé par [otpChannel] à [sentTo].
  final bool requiresConfirmation;
  final String? otpChannel;
  final String? sentTo;
  final DateTime? otpExpiresAt;
  final String? targetHolderName;
  final String? targetLast4;

  /// Bénéficiaire d'un retrait Mobile Money (lu sur l'opération : nom vérifié B-MO).
  final OperationParty? beneficiary;

  bool get isCardOperation => path == PaymentPath.cardOperation;
  bool get isExternal => path == PaymentPath.catalogExternal;

  /// Échéance affichée (« Prix garanti m:ss »).
  DateTime get guaranteedUntil => isCardOperation ? expiresAt : expiresAt.subtract(safetyMargin);

  bool isExpired(DateTime now) => !now.isBefore(guaranteedUntil);

  /// `PAYER_APPROVAL` | `CONFIRMATION_CODE` (portefeuille).
  String? get fundingApproval => display['fundingApproval'] as String?;

  List<QuoteCheck> get failedChecks => checks.where((c) => !c.passed).toList();

  PaymentQuote withBeneficiary(OperationParty? party) => PaymentQuote(
    service: service,
    path: path,
    amount: amount,
    fee: fee,
    amountDebited: amountDebited,
    amountCredited: amountCredited,
    expiresAt: expiresAt,
    feasible: feasible,
    reason: reason,
    quoteId: quoteId,
    operationId: operationId,
    checks: checks,
    warnings: warnings,
    display: display,
    requiresConfirmation: requiresConfirmation,
    otpChannel: otpChannel,
    sentTo: sentTo,
    otpExpiresAt: otpExpiresAt,
    targetHolderName: targetHolderName,
    targetLast4: targetLast4,
    beneficiary: party,
  );
}

/// Résultat d'une confirmation : `ConfirmQuoteResponseDto` / `ExecutionResponseDto` (catalogue,
/// code B-MO) ou `ConfirmOperationResponseDto` (`execute` / `confirm` d'une opération carte).
class ExecutionResult {
  const ExecutionResult({
    required this.operationId,
    required this.status,
    required this.completed,
    this.reference,
    this.awaiting,
    this.message,
    this.providerReference,
  });

  factory ExecutionResult.fromJson(Json j) {
    final status = OperationStatus.fromApi(j.strOrNull('status'));
    final details = j['details'] is Map ? j.obj('details') : const <String, dynamic>{};
    return ExecutionResult(
      operationId: j.str('operationId'),
      status: status,
      completed: j['completed'] as bool? ?? status.isSuccess,
      reference: j.strOrNull('reference'),
      awaiting: j.strOrNull('awaiting'),
      message: j.strOrNull('message'),
      providerReference:
          j.strOrNull('providerReference') ??
          details['providerReference'] as String? ??
          details['sourceReference'] as String?,
    );
  }

  final String operationId;
  final OperationStatus status;

  /// `true` = service rendu ; `false` = rien de livré (attente du payeur, du prestataire…).
  final bool completed;
  final String? reference;

  /// `PAYER_APPROVAL` | `CONFIRMATION_CODE` | `PROVIDER_SETTLEMENT`.
  final String? awaiting;
  final String? message;
  final String? providerReference;

  static const payerApproval = 'PAYER_APPROVAL';
  static const confirmationCode = 'CONFIRMATION_CODE';
  static const providerSettlement = 'PROVIDER_SETTLEMENT';
}

/// Portefeuille Mobile Money (`GET /external-wallets/channels`).
class WalletChannel {
  const WalletChannel({
    required this.slug,
    required this.label,
    this.holderVerification = false,
    this.collectApproval,
    this.placeholder,
  });

  factory WalletChannel.fromJson(Json j) {
    String? placeholder;
    final fields = j.list('payoutFields');
    if (fields.isNotEmpty && fields.first['validation'] is Map) {
      final v = fields.first.obj('validation');
      final bj = v['byCountry'] is Map ? (v['byCountry'] as Map)['BJ'] : null;
      placeholder = bj is Map ? bj['placeholder'] as String? : null;
    }
    return WalletChannel(
      slug: j.str('providerSlug'),
      label: j.strOrNull('displayName') ?? j.str('providerSlug'),
      holderVerification: j.boolean('holderVerification'),
      collectApproval: j.strOrNull('collectApproval'),
      placeholder: placeholder,
    );
  }

  /// `providerSlug`, à reporter tel quel.
  final String slug;
  final String label;

  /// B-MO : titulaire vérifié, nom du tiers facultatif, code de confirmation par SMS.
  final bool holderVerification;
  final String? collectApproval;
  final String? placeholder;

  /// Prénom et nom exigés (tout portefeuille sauf B-MO).
  bool get requiresNames => !holderVerification;
}

/// Produit opérateur (`GET /catalog/lookup/mobile/:msisdn/products`).
class MobileProduct {
  const MobileProduct({
    required this.id,
    required this.name,
    required this.priceType,
    this.price,
    this.minPrice,
    this.maxPrice,
  });

  factory MobileProduct.fromJson(Json j) => MobileProduct(
    id: j.str('id'),
    name: j.str('name'),
    priceType: j.strOrNull('priceType') ?? 'FIXED',
    price: j['price'] as num?,
    minPrice: j['minPrice'] as num?,
    maxPrice: j['maxPrice'] as num?,
  );

  final String id;
  final String name;

  /// `FIXED` (prix imposé) | `RANGE` (montant libre entre [minPrice] et [maxPrice]).
  final String priceType;
  final num? price;
  final num? minPrice;
  final num? maxPrice;

  bool get isRange => priceType == 'RANGE';
}

/// Demande de paiement construite depuis le formulaire (rejouable pour un nouveau devis).
class PaymentRequest {
  const PaymentRequest({
    required this.service,
    required this.path,
    this.cardBody = const {},
    this.funding = const {},
    this.input = const {},
    this.walletLabel,
    this.accessCode,
  });

  final ServiceType service;
  final PaymentPath path;

  /// Corps de `/cards/*/initiate` (sans `requestId`, ajouté à chaque tentative).
  final Json cardBody;

  /// `funding` et `input` de `POST /catalog/quote`.
  final Json funding;
  final Json input;

  /// Libellé du portefeuille choisi (affichage).
  final String? walletLabel;

  /// Code d'accès du retrait au guichet choisi par le porteur (non transmis au bénéficiaire).
  final String? accessCode;
}

/// Abonnement TV en cours (`GET /catalog/lookup/tv/:numCard/current`) : bouquet et prix de reconduction.
class TvCurrentOffer {
  const TvCurrentOffer({required this.numCard, required this.amount, required this.mainOfferLabel, this.currency});

  factory TvCurrentOffer.fromJson(Json j) => TvCurrentOffer(
    numCard: j.str('numCard'),
    amount: (j['amount'] as num?) ?? 0,
    currency: j.strOrNull('currency'),
    mainOfferLabel: j.strOrNull('mainOfferLabel') ?? '',
  );

  final String numCard;

  /// Prix (indicatif) de la reconduction : le devis fixe le prix réel.
  final num amount;
  final String? currency;
  final String mainOfferLabel;
}

/// Durée ou option d'un bouquet TV (`durationsList[]`, `optionsList[]`).
class TvChoice {
  const TvChoice({required this.code, required this.label, this.amount});

  factory TvChoice.fromJson(Json j) =>
      TvChoice(code: j.str('code'), label: j.strOrNull('label') ?? j.str('code'), amount: j['amount'] as num?);

  /// Transmis tel que le fournisseur le rend (`input.duration`, `input.optionsList`).
  final String code;
  final String label;

  /// Prix indicatif (options).
  final num? amount;
}

/// Bouquet TV (`GET /catalog/lookup/tv/:numCard/offers` → `offersList[]`), prix indicatifs.
class TvOffer {
  const TvOffer({
    required this.code,
    required this.label,
    required this.amount,
    this.durations = const [],
    this.options = const [],
  });

  factory TvOffer.fromJson(Json j) => TvOffer(
    code: j.str('code'),
    label: j.strOrNull('label') ?? j.str('code'),
    amount: (j['amount'] as num?) ?? 0,
    durations: j.list('durationsList').map(TvChoice.fromJson).toList(),
    options: j.list('optionsList').map(TvChoice.fromJson).toList(),
  );

  /// → `input.mainOffer`.
  final String code;
  final String label;
  final num amount;
  final List<TvChoice> durations;
  final List<TvChoice> options;
}

/// Facture d'électricité impayée (`invoices[]` du lookup SBEE).
class ElectricityInvoice {
  const ElectricityInvoice({required this.reference, required this.amount, required this.month, required this.year});

  factory ElectricityInvoice.fromJson(Json j) => ElectricityInvoice(
    reference: j.str('reference'),
    amount: (j['amount'] as num?) ?? 0,
    month: j.strOrNull('month') ?? '',
    year: j.strOrNull('year') ?? '',
  );

  /// → `input.invoiceReferences[]`.
  final String reference;
  final num amount;
  final String month;
  final String year;

  /// « MM/AAAA ».
  String get period => '$month/$year';
}

/// Abonné SBEE et factures impayées (`GET /catalog/lookup/electricity/:customerReference/invoices`).
class ElectricityAccount {
  const ElectricityAccount({required this.reference, required this.name, this.invoices = const []});

  factory ElectricityAccount.fromJson(Json j) => ElectricityAccount(
    reference: j.strOrNull('referenceAbonne') ?? '',
    name: j.strOrNull('name') ?? '',
    invoices: j.list('invoices').map(ElectricityInvoice.fromJson).toList(),
  );

  final String reference;
  final String name;
  final List<ElectricityInvoice> invoices;
}
