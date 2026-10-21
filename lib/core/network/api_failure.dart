import 'package:dio/dio.dart';

/// Codes d'erreur de l'API CardConnect v2 (guide §1.5 et codes métier par route).
abstract final class ErrorCodes {
  // Génériques
  static const validationFailed = 'VALIDATION_FAILED';
  static const requestRejected = 'REQUEST_REJECTED';
  static const unauthenticated = 'UNAUTHENTICATED';
  static const sessionExpired = 'SESSION_EXPIRED';
  static const forbidden = 'FORBIDDEN';
  static const notFound = 'NOT_FOUND';
  static const conflict = 'CONFLICT';
  static const rateLimited = 'RATE_LIMITED';
  static const providerUnavailable = 'PROVIDER_UNAVAILABLE';
  static const internalError = 'INTERNAL_ERROR';

  // Code secret
  static const pinTooWeak = 'PIN_TOO_WEAK';
  static const pinAlreadyDefined = 'PIN_ALREADY_DEFINED';
  static const pinCodeInvalid = 'PIN_CODE_INVALID';
  static const pinCodeExpired = 'PIN_CODE_EXPIRED';
  static const pinCodeExhausted = 'PIN_CODE_EXHAUSTED';
  static const pinCodeAlreadyUsed = 'PIN_CODE_ALREADY_USED';
  static const pinCodeRateLimited = 'PIN_CODE_RATE_LIMITED';

  // Paiements
  static const quoteExpired = 'QUOTE_EXPIRED';
  static const quoteRateLimit = 'QUOTE_RATE_LIMIT';
  static const dailyOperationLimit = 'DAILY_OPERATION_LIMIT';
  static const dailyAmountLimit = 'DAILY_AMOUNT_LIMIT';
  static const insufficientFunds = 'INSUFFICIENT_FUNDS';
  static const cardConsentRequired = 'CARD_CONSENT_REQUIRED';

  // Côté app
  static const network = 'NETWORK_ERROR';
  static const timeout = 'TIMEOUT';
  static const unknown = 'UNKNOWN';
}

/// Erreur affichable : message + code + référence de requête (pour le support).
///
/// Format API (guide §1.5) :
/// `{ statusCode, code, message, details, timestamp, path, requestId }`.
class ApiFailure implements Exception {
  const ApiFailure({required this.code, required this.message, this.ref, this.statusCode, this.details = const {}});

  /// Erreur produite côté app (validation locale).
  factory ApiFailure.local(String code, String message) => ApiFailure(code: code, message: message);

  factory ApiFailure.fromDio(DioException e) {
    final requestId = e.requestOptions.headers['X-Request-Id'] as String?;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiFailure(
          code: ErrorCodes.timeout,
          message: 'Le service met trop de temps à répondre. Réessayez.',
          ref: requestId,
        );
      case DioExceptionType.connectionError:
        return ApiFailure(
          code: ErrorCodes.network,
          message: 'Connexion impossible. Vérifiez votre réseau.',
          ref: requestId,
        );
      default:
        break;
    }
    final res = e.response;
    final data = res?.data;
    final status = res?.statusCode ?? 0;
    if (data is Map && data['code'] is String) {
      final code = data['code'] as String;
      final details = data['details'];
      return ApiFailure(
        code: code,
        message: userMessage(code, data['message'] as String?, data['requestId'] as String? ?? requestId),
        ref: data['requestId'] as String? ?? requestId,
        statusCode: (data['statusCode'] as num?)?.toInt() ?? res?.statusCode,
        details: details is Map ? Map<String, dynamic>.from(details) : const {},
      );
    }
    final code = status >= 500 ? ErrorCodes.internalError : ErrorCodes.unknown;
    return ApiFailure(
      code: code,
      message: userMessage(code, null, requestId),
      ref: requestId,
      statusCode: status == 0 ? null : status,
    );
  }

  static ApiFailure from(Object error) {
    if (error is ApiFailure) return error;
    if (error is DioException) {
      return error.error is ApiFailure ? error.error! as ApiFailure : ApiFailure.fromDio(error);
    }
    return ApiFailure(code: ErrorCodes.unknown, message: userMessage(ErrorCodes.unknown, null, null));
  }

  /// Message à afficher (recette §7.6) : les messages métier du serveur sont déjà rédigés
  /// pour le porteur ; seuls quelques codes génériques ont un texte imposé.
  static String userMessage(String code, String? serverMessage, String? requestId) => switch (code) {
    ErrorCodes.rateLimited => 'Trop de tentatives. Patientez une minute.',
    ErrorCodes.providerUnavailable =>
      serverMessage ?? 'Service partenaire momentanément indisponible. Réessayez dans un instant.',
    ErrorCodes.internalError => serverMessage ?? 'Erreur inattendue. Réessayez dans un instant.',
    ErrorCodes.unauthenticated ||
    ErrorCodes.sessionExpired => serverMessage ?? 'Votre session a expiré. Reconnectez-vous.',
    _ => serverMessage ?? 'Une erreur est survenue. Réessayez.',
  };

  final String code;
  final String message;
  final String? ref;
  final int? statusCode;

  /// Pour `VALIDATION_FAILED` : messages par champ (`{ "last4Digits": ["Quatre chiffres attendus."] }`).
  /// Pour certains codes métier : données complémentaires (`attemptsLeft`…).
  final Map<String, dynamic> details;

  /// Messages d'erreur d'un champ (`VALIDATION_FAILED`).
  List<String> fieldErrors(String field) {
    final v = details[field];
    if (v is List) return v.map((e) => '$e').toList();
    if (v is String) return [v];
    return const [];
  }

  bool get isUnauthenticated => code == ErrorCodes.unauthenticated || code == ErrorCodes.sessionExpired;

  @override
  String toString() => 'ApiFailure($code, $message, ref: $ref)';
}
