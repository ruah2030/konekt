import 'package:dio/dio.dart';

/// Codes d'erreur métier renvoyés par l'API (`error.code`).
abstract final class ErrorCodes {
  static const validationFailed = 'VALIDATION_FAILED';
  static const requestRejected = 'REQUEST_REJECTED';
  static const unauthenticated = 'UNAUTHENTICATED';
  static const pinCodeInvalid = 'PIN_CODE_INVALID';
  static const pinTooWeak = 'PIN_TOO_WEAK';
  static const forbidden = 'FORBIDDEN';
  static const dailyAmountLimit = 'DAILY_AMOUNT_LIMIT';
  static const insufficientFunds = 'INSUFFICIENT_FUNDS';
  static const notFound = 'NOT_FOUND';
  static const network = 'NETWORK_ERROR';
  static const timeout = 'TIMEOUT';
  static const server = 'SERVER_ERROR';
  static const unknown = 'UNKNOWN';
}

/// Erreur affichable : message + code + référence de requête (pour le support).
class ApiFailure implements Exception {
  const ApiFailure({required this.code, required this.message, this.ref, this.statusCode, this.details = const {}});

  /// Erreur produite côté app (validation locale) : on génère tout de même une
  /// référence pour garder un affichage homogène.
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
          message: 'Pas de connexion internet. Vérifiez votre réseau.',
          ref: requestId,
        );
      default:
        break;
    }
    final res = e.response;
    final data = res?.data;
    if (data is Map && data['error'] is Map) {
      final err = Map<String, dynamic>.from(data['error'] as Map);
      return ApiFailure(
        code: err['code'] as String? ?? ErrorCodes.unknown,
        message: err['message'] as String? ?? defaultMessage(err['code'] as String?),
        ref: err['requestId'] as String? ?? requestId,
        statusCode: res?.statusCode,
        details: err['details'] is Map ? Map<String, dynamic>.from(err['details'] as Map) : const {},
      );
    }
    final status = res?.statusCode ?? 0;
    return ApiFailure(
      code: status >= 500 ? ErrorCodes.server : ErrorCodes.unknown,
      message: defaultMessage(status >= 500 ? ErrorCodes.server : null),
      ref: requestId,
      statusCode: status == 0 ? null : status,
    );
  }

  static ApiFailure from(Object error) {
    if (error is ApiFailure) return error;
    if (error is DioException) {
      return error.error is ApiFailure ? error.error! as ApiFailure : ApiFailure.fromDio(error);
    }
    return ApiFailure(code: ErrorCodes.unknown, message: defaultMessage(null));
  }

  static String defaultMessage(String? code) => switch (code) {
    ErrorCodes.unauthenticated => 'Votre session a expiré. Reconnectez-vous.',
    ErrorCodes.insufficientFunds => 'Solde insuffisant.',
    ErrorCodes.dailyAmountLimit => 'Plafond journalier atteint.',
    ErrorCodes.server => 'Service momentanément indisponible. Réessayez plus tard.',
    _ => 'Une erreur est survenue. Réessayez.',
  };

  final String code;
  final String message;
  final String? ref;
  final int? statusCode;
  final Map<String, dynamic> details;

  bool get isUnauthenticated => code == ErrorCodes.unauthenticated;

  @override
  String toString() => 'ApiFailure($code, $message, ref: $ref)';
}
