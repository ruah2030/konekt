import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/json.dart';
import '../../../core/network/dio_client.dart';

/// Code de vérification envoyé (`pin/setup/request`, `pin/reset/request`).
class PinCodeSent {
  const PinCodeSent({required this.channelsUsed, required this.maskedContacts, required this.expiryMinutes});

  factory PinCodeSent.fromJson(Json j) => PinCodeSent(
    channelsUsed: j.strings('channelsUsed'),
    maskedContacts: j.strings('maskedContacts'),
    expiryMinutes: j.intOrNull('expiryMinutes') ?? 5,
  );

  final List<String> channelsUsed;
  final List<String> maskedContacts;
  final int expiryMinutes;

  /// « +**********456 et pi***@example.com ».
  String get destinationLabel {
    if (maskedContacts.isEmpty) return 'vos contacts';
    if (maskedContacts.length == 1) return maskedContacts.first;
    return '${maskedContacts.sublist(0, maskedContacts.length - 1).join(', ')} et ${maskedContacts.last}';
  }
}

/// Code secret du porteur (`/auth/customer/pin*`, guide §2.7).
/// Les PIN ne sont jamais loggés ni persistés : ils ne font que transiter.
class PinRepository {
  PinRepository(this._dio);
  final Dio _dio;

  Future<PinCodeSent> _request(String path) async =>
      PinCodeSent.fromJson((await _dio.post<Map<String, dynamic>>(path)).data ?? const {});

  /// `POST /auth/customer/pin/setup/request` (sans corps) : envoie le code de vérification de création.
  Future<PinCodeSent> requestSetupCode() => _request('/auth/customer/pin/setup/request');

  /// `POST /auth/customer/pin` (201) : définit le premier code secret.
  Future<void> create({required String pin, required String code}) =>
      _dio.post<void>('/auth/customer/pin', data: {'pin': pin, 'code': code});

  /// `POST /auth/customer/pin/change`.
  Future<void> change({required String currentPin, required String pin}) =>
      _dio.post<void>('/auth/customer/pin/change', data: {'currentPin': currentPin, 'pin': pin});

  /// `POST /auth/customer/pin/reset/request` (sans corps) : code oublié.
  Future<PinCodeSent> requestResetCode() => _request('/auth/customer/pin/reset/request');

  /// `POST /auth/customer/pin/reset/confirm` : remplace le code secret et lève le verrouillage.
  Future<void> confirmReset({required String code, required String pin}) =>
      _dio.post<void>('/auth/customer/pin/reset/confirm', data: {'code': code, 'pin': pin});
}

final pinRepositoryProvider = Provider<PinRepository>((ref) => PinRepository(ref.watch(dioProvider)));
