import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/json.dart';
import '../../../core/network/dio_client.dart';

/// État du code secret côté serveur (`GET /v1/pin/status`).
class PinStatus {
  const PinStatus({required this.hasPin, required this.triesLeft, this.lockedUntil});

  factory PinStatus.fromJson(Json j) => PinStatus(
    hasPin: j.boolean('hasPin'),
    triesLeft: j.integer('triesLeft'),
    lockedUntil: j.dateOrNull('lockedUntil'),
  );

  final bool hasPin;
  final int triesLeft;
  final DateTime? lockedUntil;

  bool isLocked(DateTime now) => lockedUntil != null && now.isBefore(lockedUntil!);
}

/// Création, vérification, changement et réinitialisation du code secret.
/// Les PIN ne sont jamais loggés ni persistés : ils ne font que transiter.
class PinRepository {
  PinRepository(this._dio);
  final Dio _dio;

  /// Envoie un code de vérification par SMS et par e-mail. Renvoie les destinations masquées.
  Future<List<String>> requestVerification() async {
    final j = (await _dio.post<Map<String, dynamic>>('/v1/pin/verification')).data ?? const {};
    return j.strings('maskedDestinations');
  }

  /// Valide le code de vérification et renvoie un `verificationToken`.
  Future<String> confirmVerification(String code) async {
    final j = (await _dio.post<Map<String, dynamic>>('/v1/pin/verification/confirm', data: {'code': code})).data!;
    return j.str('verificationToken');
  }

  /// Création du premier code secret.
  Future<void> create({required String verificationToken, required String pin}) =>
      _dio.post<void>('/v1/pin', data: {'verificationToken': verificationToken, 'pin': pin});

  /// Vérifie le code secret actuel (flux de changement, étape « Code secret actuel »).
  Future<void> check(String pin) => _dio.post<void>('/v1/pin/check', data: {'pin': pin});

  Future<void> change({required String currentPin, required String newPin}) =>
      _dio.put<void>('/v1/pin', data: {'currentPin': currentPin, 'newPin': newPin});

  /// Code oublié : remplace le code secret et lève un éventuel verrouillage.
  Future<void> reset({required String verificationToken, required String pin}) =>
      _dio.post<void>('/v1/pin/reset', data: {'verificationToken': verificationToken, 'pin': pin});

  Future<PinStatus> status() async =>
      PinStatus.fromJson((await _dio.get<Map<String, dynamic>>('/v1/pin/status')).data!);
}

final pinRepositoryProvider = Provider<PinRepository>((ref) => PinRepository(ref.watch(dioProvider)));
