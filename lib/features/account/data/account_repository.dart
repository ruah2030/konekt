import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/app_notification.dart';
import '../../../core/domain/card.dart';
import '../../../core/domain/json.dart';
import '../../../core/domain/operation.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/transaction.dart';
import '../../../core/network/dio_client.dart';

/// Page de résultats paginés par curseur.
class Page<T> {
  const Page(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

class SystemIncident {
  const SystemIncident({required this.id, required this.message});
  factory SystemIncident.fromJson(Json j) => SystemIncident(id: j.str('id'), message: j.str('message'));
  final String id;
  final String message;
}

/// Lecture des données de compte partagées par plusieurs écrans
/// (accueil, historique, carte, profil, notifications).
class AccountRepository {
  AccountRepository(this._dio);
  final Dio _dio;

  Future<Json> _get(String path, [Map<String, dynamic>? q]) async =>
      (await _dio.get<Map<String, dynamic>>(path, queryParameters: q)).data!;

  Future<Holder> me() async => Holder.fromJson(await _get('/v1/me'));

  Future<CardInfo> card() async => CardInfo.fromJson(await _get('/v1/card'));

  Future<int> balance() async => (await _get('/v1/card/balance')).integer('available');

  Future<Page<CardTransaction>> transactions({String? cursor, int limit = 20}) async {
    final j = await _get('/v1/card/transactions', {'limit': limit, 'cursor': ?cursor});
    return Page(j.list('items').map(CardTransaction.fromJson).toList(), j.strOrNull('nextCursor'));
  }

  Future<Page<Operation>> operations({String? cursor, int limit = 20}) async {
    final j = await _get('/v1/operations', {'limit': limit, 'cursor': ?cursor});
    return Page(j.list('items').map(Operation.fromJson).toList(), j.strOrNull('nextCursor'));
  }

  Future<Operation> operation(String id) async => Operation.fromJson(await _get('/v1/operations/$id'));

  Future<List<AppNotification>> notifications() async =>
      (await _get('/v1/notifications')).list('items').map(AppNotification.fromJson).toList();

  Future<void> markNotificationRead(String id) => _dio.post<void>('/v1/notifications/$id/read');

  Future<void> markAllNotificationsRead() => _dio.post<void>('/v1/notifications/read-all');

  Future<List<Promotion>> promotions(PromoPlacement placement) async =>
      (await _get('/v1/promotions', {'placement': placement.name})).list('items').map(Promotion.fromJson).toList();

  Future<List<SystemIncident>> incidents() async =>
      (await _get('/v1/status')).list('incidents').map(SystemIncident.fromJson).toList();
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) => AccountRepository(ref.watch(dioProvider)));
