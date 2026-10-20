import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/operation.dart';
import '../../../../core/domain/service_type.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/utils/validators.dart';
import '../../../account/presentation/account_providers.dart';
import '../../data/payment_repository.dart';
import '../../domain/payment_models.dart';
import '../../domain/service_config.dart';

/// État du parcours de paiement : formulaire → devis → PIN → traitement → reçu.
class PaymentFlowState {
  const PaymentFlowState({
    this.service,
    this.form = const {},
    this.option,
    this.quote,
    this.operation,
    this.quoting = false,
    this.submitting = false,
    this.quoteError,
    this.pinError,
    this.pinLockedUntil,
  });

  final ServiceType? service;
  final Map<String, String> form;
  final String? option;
  final Quote? quote;
  final Operation? operation;

  /// Devis en cours de calcul.
  final bool quoting;

  /// Exécution (PIN) en cours d'envoi.
  final bool submitting;

  /// Erreur lors d'un nouveau devis demandé depuis l'écran récapitulatif.
  final ApiFailure? quoteError;
  final ApiFailure? pinError;
  final DateTime? pinLockedUntil;

  ServiceConfig? get config => service == null ? null : serviceConfig(service!);

  bool isPinLocked(DateTime now) => pinLockedUntil != null && now.isBefore(pinLockedUntil!);

  PaymentFlowState copyWith({
    Quote? quote,
    Operation? operation,
    bool? quoting,
    bool? submitting,
    ApiFailure? Function()? quoteError,
    ApiFailure? Function()? pinError,
    DateTime? Function()? pinLockedUntil,
  }) => PaymentFlowState(
    service: service,
    form: form,
    option: option,
    quote: quote ?? this.quote,
    operation: operation ?? this.operation,
    quoting: quoting ?? this.quoting,
    submitting: submitting ?? this.submitting,
    quoteError: quoteError == null ? this.quoteError : quoteError(),
    pinError: pinError == null ? this.pinError : pinError(),
    pinLockedUntil: pinLockedUntil == null ? this.pinLockedUntil : pinLockedUntil(),
  );
}

/// Parcours de paiement. Conservé pendant tout le flux (non autoDispose) ; réinitialisé à chaque devis.
final paymentFlowProvider = NotifierProvider<PaymentFlowController, PaymentFlowState>(PaymentFlowController.new);

class PaymentFlowController extends Notifier<PaymentFlowState> {
  @override
  PaymentFlowState build() => const PaymentFlowState();

  PaymentRepository get _repo => ref.read(paymentRepositoryProvider);

  /// Validations locales (messages de la maquette, `requestQuote`). `null` si tout est valide.
  ApiFailure? validate(ServiceConfig config, Map<String, String> form, String? option) {
    ApiFailure fail(String code, String message) => ApiFailure.local(code, message);
    final opt = config.option;
    if (opt != null && option == null) {
      return fail(ErrorCodes.validationFailed, 'Choisissez : ${opt.label.toLowerCase()}.');
    }
    for (final f in config.fields) {
      if ((form[f.key] ?? '').trim().isEmpty) {
        return fail(ErrorCodes.validationFailed, '${f.label} : champ obligatoire.');
      }
    }
    final target = form['target'];
    final sessionCard = ref.read(cardProvider).value?.id;
    if (target != null && sessionCard != null && Validators.digitsOnly(target) == sessionCard) {
      return fail(ErrorCodes.requestRejected, 'La carte bénéficiaire doit être différente de la vôtre.');
    }
    final msisdn = form['msisdn'];
    if (msisdn != null && !Validators.isMsisdn(msisdn)) {
      return fail(ErrorCodes.requestRejected, 'Numéro de téléphone invalide.');
    }
    final meter = form['meter'];
    if (meter != null && !Validators.isMeter(meter)) {
      return fail(ErrorCodes.requestRejected, 'Numéro de compteur : chiffres uniquement.');
    }
    if (!config.imposedPrice && config.hasAmountField) {
      final amount = parseAmount(form[ServiceField.amountKey] ?? '');
      if (amount == null || amount < 100) return fail(ErrorCodes.validationFailed, 'Montant minimum : 100 FCFA.');
      if (amount > 1000000) return fail(ErrorCodes.validationFailed, 'Montant maximum : 1 000 000 FCFA.');
    }
    return null;
  }

  Map<String, dynamic> _request(ServiceConfig config, Map<String, String> form, String? option) => {
    'service': config.type.id,
    for (final f in config.fields)
      if (f.isAmount)
        f.key: parseAmount(form[f.key] ?? '')
      else
        f.key: f.kind == FieldKind.numeric ? Validators.digitsOnly(form[f.key] ?? '') : (form[f.key] ?? '').trim(),
    if (config.option != null && option != null) config.option!.apiKey: option,
  };

  /// Valide le formulaire puis demande le devis. Renvoie l'erreur à afficher, ou `null` en cas de succès.
  Future<ApiFailure?> requestQuote(ServiceType service, Map<String, String> form, String? option) async {
    final config = serviceConfig(service);
    final invalid = validate(config, form, option);
    if (invalid != null) return invalid;
    state = PaymentFlowState(service: service, form: Map.unmodifiable(form), option: option, quoting: true);
    try {
      final quote = await _repo.requestQuote(_request(config, form, option));
      state = state.copyWith(quote: quote, quoting: false);
      return null;
    } catch (e) {
      state = state.copyWith(quoting: false);
      return ApiFailure.from(e);
    }
  }

  /// Nouveau devis avec le même formulaire (prix expiré).
  Future<bool> requote() async {
    final service = state.service;
    if (service == null) return false;
    final config = serviceConfig(service);
    state = state.copyWith(quoting: true, quoteError: () => null);
    try {
      final quote = await _repo.requestQuote(_request(config, state.form, state.option));
      state = PaymentFlowState(service: service, form: state.form, option: state.option, quote: quote);
      return true;
    } catch (e) {
      state = state.copyWith(quoting: false, quoteError: () => ApiFailure.from(e));
      return false;
    }
  }

  /// Exécute le paiement avec le code secret. Renvoie `true` si l'opération est lancée.
  Future<bool> submitPin(String pin) async {
    final quote = state.quote;
    if (quote == null || state.submitting) return false;
    state = state.copyWith(submitting: true, pinError: () => null);
    try {
      final op = await _repo.execute(quoteId: quote.quoteId, pin: pin);
      state = state.copyWith(operation: op, submitting: false, pinLockedUntil: () => null);
      return true;
    } catch (e) {
      final failure = ApiFailure.from(e);
      final lockedUntil = failure.details['lockedUntil'] as String?;
      state = state.copyWith(
        submitting: false,
        pinError: () => failure,
        pinLockedUntil: lockedUntil == null ? null : () => DateTime.parse(lockedUntil).toLocal(),
      );
      return false;
    }
  }

  void clearPinError() {
    if (state.pinError != null) state = state.copyWith(pinError: () => null);
  }

  /// Met à jour l'opération en cours (polling de l'écran de traitement).
  Future<Operation?> refreshOperation() async {
    final op = state.operation;
    if (op == null) return null;
    final fresh = await _repo.track(op.id);
    state = state.copyWith(operation: fresh);
    return fresh;
  }

  void reset() => state = const PaymentFlowState();
}
