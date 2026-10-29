import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/domain/operation.dart';
import '../../../../core/network/api_failure.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/payment_repository.dart';
import '../../domain/payment_models.dart';

/// Horloge du parcours (surchargeable en test).
final paymentClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Échec d'un devis : erreur à afficher et contrôles en échec (`checks[].passed:false`).
class QuoteFailure {
  const QuoteFailure(this.failure, [this.failedChecks = const []]);
  final ApiFailure failure;
  final List<QuoteCheck> failedChecks;
}

/// Issue de la saisie du code secret / code OTP.
enum SecretOutcome {
  /// Paiement lancé : écran de traitement.
  submitted,

  /// Erreur affichée sur l'écran (PIN faux, verrou…), l'utilisateur peut ressaisir.
  retry,

  /// Le devis n'est plus utilisable : en redemander un.
  requote,

  /// L'opération a été annulée (code épuisé ou expiré) : recommencer.
  restart,
}

/// État du parcours : formulaire → devis → PIN/OTP → traitement (suivi) → reçu.
class PaymentFlowState {
  const PaymentFlowState({
    this.request,
    this.quote,
    this.reference,
    this.execution,
    this.operation,
    this.quoting = false,
    this.submitting = false,
    this.quoteError,
    this.pinError,
    this.codeError,
    this.review,
    this.needsRequote = false,
    this.restartRequired = false,
    this.trackingSince,
    this.confirmSent = false,
    this.recoveredOperationId,
  });

  final PaymentRequest? request;
  final PaymentQuote? quote;

  /// Identifiant de la tentative : `reference` (catalogue) ou `requestId` (opération carte).
  /// Réutilisé tel quel pour un rejeu volontaire (réponse perdue), jamais pour un nouveau devis.
  final String? reference;
  final ExecutionResult? execution;

  /// Dernier état lu de l'opération (`GET /cards/operations/:id`).
  final Operation? operation;
  final bool quoting;
  final bool submitting;
  final ApiFailure? quoteError;
  final ApiFailure? pinError;

  /// Erreur de saisie du code B-MO.
  final ApiFailure? codeError;

  /// Sort incertain (500 « NE LA RELANCEZ PAS », incident) : écran « en vérification ».
  final ApiFailure? review;
  final bool needsRequote;
  final bool restartRequired;
  final DateTime? trackingSince;

  /// Une confirmation du catalogue est partie sans réponse certaine (coupure réseau, 5xx,
  /// « déjà en cours de traitement ») : le paiement a peut-être abouti. Dès lors, JAMAIS de nouveau
  /// devis ni de nouvelle `reference` : on renvoie la même ou on suit l'opération (règle d'or n° 3).
  final bool confirmSent;

  /// Opération retrouvée par sa `reference` (catalogue sans `operationId` connu).
  final String? recoveredOperationId;

  /// Paiement du catalogue au sort incertain dont l'opération reste à retrouver par sa `reference`.
  bool get canSearchOperation =>
      operationId == null && confirmSent && reference != null && quote != null && !quote!.isCardOperation;

  /// Opération à suivre.
  String? get operationId =>
      execution?.operationId ?? recoveredOperationId ?? (review != null ? quote?.operationId : null);

  /// `awaiting` courant (exécution, puis suivi).
  String? get awaiting {
    final op = operation;
    if (op != null) return op.status == OperationStatus.pending ? op.awaiting : null;
    return execution?.awaiting;
  }

  PaymentFlowState copyWith({
    PaymentQuote? Function()? quote,
    String? Function()? reference,
    ExecutionResult? Function()? execution,
    Operation? Function()? operation,
    bool? quoting,
    bool? submitting,
    ApiFailure? Function()? quoteError,
    ApiFailure? Function()? pinError,
    ApiFailure? Function()? codeError,
    ApiFailure? Function()? review,
    bool? needsRequote,
    bool? restartRequired,
    DateTime? Function()? trackingSince,
    bool? confirmSent,
    String? Function()? recoveredOperationId,
  }) => PaymentFlowState(
    request: request,
    quote: quote == null ? this.quote : quote(),
    reference: reference == null ? this.reference : reference(),
    execution: execution == null ? this.execution : execution(),
    operation: operation == null ? this.operation : operation(),
    quoting: quoting ?? this.quoting,
    submitting: submitting ?? this.submitting,
    quoteError: quoteError == null ? this.quoteError : quoteError(),
    pinError: pinError == null ? this.pinError : pinError(),
    codeError: codeError == null ? this.codeError : codeError(),
    review: review == null ? this.review : review(),
    needsRequote: needsRequote ?? this.needsRequote,
    restartRequired: restartRequired ?? this.restartRequired,
    trackingSince: trackingSince == null ? this.trackingSince : trackingSince(),
    confirmSent: confirmSent ?? this.confirmSent,
    recoveredOperationId: recoveredOperationId == null ? this.recoveredOperationId : recoveredOperationId(),
  );
}

/// Parcours de paiement. Conservé pendant tout le flux (non autoDispose) ; réinitialisé à chaque devis.
final paymentFlowProvider = NotifierProvider<PaymentFlowController, PaymentFlowState>(PaymentFlowController.new);

class PaymentFlowController extends Notifier<PaymentFlowState> {
  @override
  PaymentFlowState build() => const PaymentFlowState();

  PaymentRepository get _repo => ref.read(paymentRepositoryProvider);
  DateTime _now() => ref.read(paymentClockProvider)();
  String _uuid() => const Uuid().v4();

  /// Demande un devis (catalogue) ou initie l'opération carte (frais arrêtés). `null` si réussi.
  Future<QuoteFailure?> requestQuote(PaymentRequest request) async {
    await abandon();
    state = PaymentFlowState(request: request, quoting: true);
    final failure = await _quote(request);
    if (failure != null) state = state.copyWith(quoting: false);
    return failure;
  }

  Future<QuoteFailure?> _quote(PaymentRequest request) async {
    try {
      final reference = _uuid();
      var quote = request.path == PaymentPath.cardOperation
          ? await _repo.initiate(request, requestId: reference, now: _now())
          : await _repo.catalogQuote(request);
      if (!quote.feasible) {
        return QuoteFailure(
          ApiFailure.local(ErrorCodes.requestRejected, quote.reason ?? 'Opération impossible.'),
          quote.failedChecks,
        );
      }
      if (quote.isCardOperation && quote.targetLast4 == null) {
        // Retrait Mobile Money : nom du bénéficiaire retenu (vérifié chez B-MO) lu sur l'opération.
        try {
          final op = await _repo.operation(quote.operationId!);
          quote = quote.withBeneficiary(op.parties.where((p) => p.role == 'BENEFICIARY').firstOrNull);
        } catch (_) {
          // Affichage seulement : le récapitulatif reprend la saisie.
        }
      }
      state = PaymentFlowState(request: request, quote: quote, reference: reference);
      return null;
    } catch (e) {
      return QuoteFailure(ApiFailure.from(e));
    }
  }

  /// Nouveau devis avec la même demande (prix expiré, devis consommé). L'opération carte en
  /// attente est annulée avant d'en initier une nouvelle (nouveau `requestId`).
  Future<bool> requote() async {
    final request = state.request;
    if (request == null || state.confirmSent) return false;
    await abandon();
    state = state.copyWith(quoting: true, quoteError: () => null);
    final failure = await _quote(request);
    if (failure != null) {
      state = state.copyWith(quoting: false, quoteError: () => failure.failure);
      return false;
    }
    return true;
  }

  /// Abandon d'une opération carte initiée et non conclue : `DELETE /cards/operations/:id`.
  Future<void> abandon() async {
    final q = state.quote;
    if (q == null || !q.isCardOperation || state.execution != null || state.review != null) return;
    state = state.copyWith(quote: () => null);
    try {
      await _repo.cancel(q.operationId!);
    } catch (_) {
      // Déjà conclue, annulée ou introuvable : rien à faire.
    }
  }

  /// Confirme avec le code secret (catalogue par carte, `execute`) ou le code OTP (`confirm`).
  Future<SecretOutcome> submitSecret(String code) async {
    final q = state.quote;
    final request = state.request;
    if (q == null || request == null || state.submitting) return SecretOutcome.retry;
    if (!q.isCardOperation && !state.confirmSent && q.isExpired(_now())) {
      // PIN vérifié avant le devis côté serveur : ne pas risquer un essai pour un devis périmé.
      state = state.copyWith(needsRequote: true);
      return SecretOutcome.requote;
    }
    state = state.copyWith(submitting: true, pinError: () => null);
    try {
      final result = switch (q.path) {
        PaymentPath.cardOperation =>
          q.requiresConfirmation
              ? await _repo.confirmOtp(q.operationId!, code)
              : await _repo.execute(q.operationId!, code),
        _ => await _repo.catalogConfirm(request: request, quoteId: q.quoteId!, reference: state.reference!, pin: code),
      };
      _executed(result);
      return SecretOutcome.submitted;
    } catch (e) {
      return _secretFailed(ApiFailure.from(e));
    }
  }

  /// Confirmation sans PIN (catalogue payé par un portefeuille mobile).
  Future<ApiFailure?> confirmExternal() async {
    final q = state.quote;
    final request = state.request;
    if (q == null || request == null || state.submitting) return null;
    state = state.copyWith(submitting: true, quoteError: () => null);
    try {
      _executed(await _repo.catalogConfirm(request: request, quoteId: q.quoteId!, reference: state.reference!));
      return null;
    } catch (e) {
      final f = ApiFailure.from(e);
      if (_uncertain(f) || _alreadyProcessing(f) || (state.confirmSent && _lostResponse(f))) {
        _toReview(f);
        return null;
      }
      if (_lostResponse(f)) {
        // Réponse perdue : la même référence sera renvoyée (idempotent), jamais une nouvelle.
        state = state.copyWith(submitting: false, quoteError: () => _lostResponseFailure(f), confirmSent: true);
        return f;
      }
      state = state.copyWith(
        submitting: false,
        quoteError: () => f,
        needsRequote: !state.confirmSent && _burnsQuote(f),
      );
      return f;
    }
  }

  void _executed(ExecutionResult r) {
    state = state.copyWith(
      submitting: false,
      execution: () => r,
      pinError: () => null,
      review: () => null,
      trackingSince: _now,
    );
  }

  /// Coupure réseau ou délai dépassé : la requête est peut-être arrivée au serveur.
  bool _lostResponse(ApiFailure f) => f.code == ErrorCodes.network || f.code == ErrorCodes.timeout;

  /// « Une vente portant la référence … est déjà en cours de traitement » (§2.6) : un envoi précédent
  /// avec la même référence est en cours — c'est un paiement à suivre, pas un refus.
  bool _alreadyProcessing(ApiFailure f) =>
      f.code == ErrorCodes.requestRejected && f.message.toLowerCase().contains('déjà en cours de traitement');

  ApiFailure _lostResponseFailure(ApiFailure f) => ApiFailure(
    code: f.code,
    message:
        'La connexion a été interrompue : le paiement a peut-être abouti. Réessayez pour vérifier — la même '
        'demande sera renvoyée, sans risque de double paiement.',
    ref: f.ref,
  );

  /// Sort incertain : écran « en vérification » et suivi de l'opération (retrouvée par sa référence au besoin).
  void _toReview(ApiFailure f) {
    state = state.copyWith(
      submitting: false,
      review: () => f,
      trackingSince: _now,
      confirmSent: state.quote?.isCardOperation == false ? true : null,
    );
  }

  /// 5xx ou réponse perdue : le sort est incertain, on suit l'opération sans jamais relancer.
  bool _uncertain(ApiFailure f) =>
      (f.statusCode ?? 0) >= 500 || f.code == ErrorCodes.internalError || f.code == 'FUNDING_UNCERTAIN';

  /// Le devis est consommé ou périmé : il faut en redemander un.
  bool _burnsQuote(ApiFailure f) =>
      f.code == ErrorCodes.requestRejected ||
      f.code == ErrorCodes.dailyAmountLimit ||
      f.code == ErrorCodes.dailyOperationLimit ||
      f.code == ErrorCodes.notFound;

  Future<SecretOutcome> _secretFailed(ApiFailure f) async {
    final q = state.quote!;
    if (_uncertain(f) || (!q.isCardOperation && _alreadyProcessing(f))) {
      _toReview(f);
      return SecretOutcome.submitted;
    }
    if (_lostResponse(f)) {
      // Réponse perdue : un nouvel envoi réutilise la même référence (idempotent), même si le devis expire.
      state = state.copyWith(
        submitting: false,
        pinError: () => ApiFailure(
          code: f.code,
          message:
              'La connexion a été interrompue : le paiement a peut-être abouti. Ressaisissez votre code pour '
              'vérifier — la même demande sera renvoyée, sans risque de double paiement.',
          ref: f.ref,
        ),
        confirmSent: q.isCardOperation ? null : true,
      );
      return SecretOutcome.retry;
    }
    if (q.isCardOperation && f.code == ErrorCodes.requestRejected) {
      // Relire l'opération : déjà effectuée, annulée (code épuisé) ou toujours en attente ?
      try {
        final op = await _repo.operation(q.operationId!, sessionCardCustomerId: _cardId());
        if (op.status == OperationStatus.cancelled || op.status == OperationStatus.expired) {
          state = state.copyWith(submitting: false, pinError: () => f, restartRequired: true, operation: () => op);
          return SecretOutcome.restart;
        }
        if (op.status != OperationStatus.pending && op.status != OperationStatus.pendingApproval) {
          state = state.copyWith(
            submitting: false,
            execution: () => ExecutionResult(operationId: op.id, status: op.status, completed: op.status.isSuccess),
            operation: () => op,
            trackingSince: _now,
          );
          return SecretOutcome.submitted;
        }
      } catch (_) {
        // Lecture impossible : on affiche l'erreur d'origine.
      }
      final expiredCode = q.requiresConfirmation && f.message.contains('expiré');
      state = state.copyWith(submitting: false, pinError: () => f, restartRequired: expiredCode);
      return expiredCode ? SecretOutcome.restart : SecretOutcome.retry;
    }
    if (!q.isCardOperation && state.confirmSent && f.code == ErrorCodes.requestRejected) {
      // Après un envoi incertain, un refus peut venir de ce que le premier envoi a déjà consommé le devis :
      // on suit l'opération plutôt que de payer une seconde fois.
      _toReview(f);
      return SecretOutcome.submitted;
    }
    final burns = !q.isCardOperation && !state.confirmSent && _burnsQuote(f);
    state = state.copyWith(submitting: false, pinError: () => f, needsRequote: burns);
    return SecretOutcome.retry;
  }

  void clearPinError() {
    if (state.pinError != null || state.needsRequote || state.restartRequired) {
      state = state.copyWith(pinError: () => null, needsRequote: false, restartRequired: false);
    }
  }

  /// Saisie du code B-MO (`funding/confirm`). `null` si accepté.
  Future<ApiFailure?> submitFundingCode(String code) async {
    final id = state.operationId;
    if (id == null || state.submitting) return null;
    state = state.copyWith(submitting: true, codeError: () => null);
    try {
      final r = await _repo.fundingConfirm(id, code);
      state = state.copyWith(submitting: false, execution: () => r, operation: () => null);
      await refreshOperation();
      return null;
    } catch (e) {
      final f = ApiFailure.from(e);
      state = state.copyWith(submitting: false, codeError: () => f);
      if (f.code == 'CONFIRMATION_ATTEMPTS_EXHAUSTED' || f.code == 'FUNDING_CLOSED') await refreshOperation();
      return f;
    }
  }

  /// Renonce au paiement B-MO (`funding/cancel`) puis relit l'opération (peut être `SUCCESS`).
  Future<ApiFailure?> cancelFunding() async {
    final id = state.operationId;
    if (id == null || state.submitting) return null;
    state = state.copyWith(submitting: true, codeError: () => null);
    try {
      final r = await _repo.fundingCancel(id);
      state = state.copyWith(submitting: false, execution: () => r);
      await refreshOperation();
      return null;
    } catch (e) {
      final f = ApiFailure.from(e);
      state = state.copyWith(submitting: false, codeError: () => f);
      return f;
    }
  }

  String? _cardId() => ref.read(cardSessionProvider)?.cardCustomerId;

  /// Relit l'opération en cours (suivi de l'écran de traitement).
  Future<Operation?> refreshOperation() async {
    var id = state.operationId;
    if (id == null && state.canSearchOperation) {
      id = await _repo.operationIdByReference(state.reference!);
      if (id == null) return null;
      state = state.copyWith(recoveredOperationId: () => id);
    }
    if (id == null) return null;
    final fresh = await _repo.operation(id, sessionCardCustomerId: _cardId());
    state = state.copyWith(operation: () => fresh);
    return fresh;
  }

  void reset() => state = const PaymentFlowState();
}
