import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/app_notification.dart';
import '../../../core/domain/card.dart';
import '../../../core/domain/json.dart';
import '../../../core/domain/operation.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/transaction.dart';
import '../../../core/network/dio_client.dart';

/// Page de résultats. [nextCursor] = numéro de la page suivante (pagination `page`/`limit` de l'API).
class Page<T> {
  const Page(this.items, this.nextCursor, {this.total});
  final List<T> items;
  final String? nextCursor;
  final int? total;
}

/// Page de notifications + pastille (`unreadCount`, indépendant des filtres).
class NotificationsPage extends Page<AppNotification> {
  const NotificationsPage(super.items, super.nextCursor, {required this.unreadCount, super.total});
  final int unreadCount;
}

/// `GET /status` : bannière globale si `overall != operational`.
class PlatformStatus {
  const PlatformStatus({required this.overall, required this.degradedServices});
  factory PlatformStatus.fromJson(Json j) => PlatformStatus(
    overall: j.strOrNull('overall') ?? 'operational',
    degradedServices: j.list('services').where((s) => s['status'] != 'HEALTHY').map((s) => '${s['name']}').toList(),
  );

  /// `operational` | `partial_outage` | `major_outage`.
  final String overall;
  final List<String> degradedServices;

  bool get hasIncident => overall != 'operational';

  String get message => degradedServices.isEmpty
      ? 'Incident en cours : certains paiements peuvent être ralentis.'
      : 'Incident en cours (${degradedServices.join(', ')}) : certains paiements peuvent être ralentis.';
}

/// Service proposé au porteur (`GET /catalog/services`, `ServiceOffer` simplifié).
class ServiceOffer {
  const ServiceOffer({
    required this.key,
    required this.label,
    required this.kind,
    required this.amountMode,
    required this.available,
    this.unavailableReason,
    this.minAmount,
    this.maxAmount,
  });

  factory ServiceOffer.fromJson(Json j) {
    final options = j.list('options');
    final open = options.where((o) => o['available'] == true).toList();
    final limits = (open.isNotEmpty ? open.first : options.firstOrNull)?['limits'];
    return ServiceOffer(
      key: j.str('key'),
      label: j.strOrNull('label') ?? j.str('key'),
      kind: j.strOrNull('kind') ?? 'CATALOG',
      amountMode: j.strOrNull('amountMode') ?? 'FREE',
      available: j.boolean('available'),
      unavailableReason: j.strOrNull('unavailableReason'),
      minAmount: limits is Map ? limits['minAmount'] as num? : null,
      maxAmount: limits is Map ? limits['maxAmount'] as num? : null,
    );
  }

  /// Clé catalogue (`mobile-topup`…) ou slug de service carte (`merchant:card:transfer`).
  final String key;
  final String label;

  /// `CATALOG` | `CARD_SERVICE`.
  final String kind;

  /// `FREE` | `IMPOSED` | `NONE`.
  final String amountMode;
  final bool available;
  final String? unavailableReason;
  final num? minAmount;
  final num? maxAmount;
}

/// Lectures partagées par plusieurs écrans (accueil, historique, carte, profil, notifications).
/// Toutes les routes portent sur la carte de session ([cardCustomerId] tel que reçu à la connexion).
class AccountRepository {
  AccountRepository(this._dio);
  final Dio _dio;

  Future<Json> _get(String path, [Map<String, dynamic>? q]) async =>
      (await _dio.get<Map<String, dynamic>>(path, queryParameters: q)).data!;

  /// `GET /cards` (carte émise sur la plateforme) ; carte externe → `GET /cards/details/:id`.
  Future<CardInfo> card(String cardCustomerId) async {
    final list = (await _get('/cards')).list('data');
    if (list.isNotEmpty) return CardInfo.fromCardsItem(list.first);
    return details(cardCustomerId);
  }

  /// État réel chez l'émetteur (fait foi sur la liste).
  Future<CardInfo> details(String cardCustomerId) async =>
      CardInfo.fromDetails((await _get('/cards/details/$cardCustomerId')).obj('card'), cardCustomerId: cardCustomerId);

  /// Solde lu en direct chez l'émetteur (jamais mis en cache).
  Future<num> balance(String cardCustomerId) async => (await _get('/cards/balance/$cardCustomerId'))['balance'] as num;

  /// Relevé émetteur sur une période (défaut API : dernier mois). Dates `AAAA-MM-JJ`.
  Future<List<CardTransaction>> transactions(String cardCustomerId, {DateTime? start, DateTime? end}) async {
    String d(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final j = await _get('/cards/transactions/$cardCustomerId', {
      if (start != null) 'startDate': d(start),
      // Une date seule vaut minuit UTC : on envoie le lendemain pour inclure la journée de fin.
      if (end != null) 'endDate': d(end.add(const Duration(days: 1))),
    });
    return CardTransaction.listFromIssuer(j.list('transactions'));
  }

  /// `GET /operations` (pagination par numéro de page, `limit` ≤ 100).
  Future<Page<Operation>> operations({required String cardCustomerId, String? cursor, int limit = 20}) async {
    final page = int.tryParse(cursor ?? '1') ?? 1;
    final j = await _get('/operations', {'page': page, 'limit': limit});
    final pagination = j['pagination'] is Map ? j.obj('pagination') : const <String, dynamic>{};
    return Page(
      j.list('data').map((o) => Operation.fromJson(o, sessionCardCustomerId: cardCustomerId)).toList(),
      pagination['hasNextPage'] == true ? '${page + 1}' : null,
      total: (pagination['total'] as num?)?.toInt(),
    );
  }

  /// `GET /operations/:id` (avec devis et mouvements).
  Future<Operation> operation(String id, {required String cardCustomerId}) async =>
      Operation.fromJson((await _get('/operations/$id')).obj('data'), sessionCardCustomerId: cardCustomerId);

  /// `GET /notifications` (`limit` ≤ 50, sinon 400).
  Future<NotificationsPage> notifications({String? cursor, int limit = 20}) async {
    final page = int.tryParse(cursor ?? '1') ?? 1;
    final j = await _get('/notifications', {'page': page, 'limit': limit.clamp(1, 50)});
    final pagination = j['pagination'] is Map ? j.obj('pagination') : const <String, dynamic>{};
    return NotificationsPage(
      j.list('data').map(AppNotification.fromJson).toList(),
      pagination['hasNextPage'] == true ? '${page + 1}' : null,
      unreadCount: j.intOrNull('unreadCount') ?? 0,
      total: (pagination['total'] as num?)?.toInt(),
    );
  }

  /// Pastille (à interroger au plus une fois par minute : le push n'est pas branché côté API).
  Future<int> unreadCount() async => (await _get('/notifications/unread-count')).intOrNull('count') ?? 0;

  /// 404 « Notification introuvable » (déjà lue…) est anodin et ignoré.
  Future<void> markNotificationRead(String id) async {
    try {
      await _dio.post<void>('/notifications/$id/read');
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
  }

  Future<void> markAllNotificationsRead() => _dio.post<void>('/notifications/read-all');

  /// Range un message (pose `archivedAt` et `readAt`).
  Future<void> archiveNotification(String id) async {
    try {
      await _dio.delete<void>('/notifications/$id');
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
  }

  /// ⚠️ Hors API CardConnect v2 (aucune route de promotions) : servi par le faux backend uniquement.
  Future<List<Promotion>> promotions(PromoPlacement placement) async =>
      (await _get('/promotions', {'placement': placement.name})).list('items').map(Promotion.fromJson).toList();

  /// `GET /status` (public).
  Future<PlatformStatus> status() async => PlatformStatus.fromJson(await _get('/status'));

  /// `GET /catalog/services` : services ouverts ou grisés (avec motif) pour ce porteur.
  Future<List<ServiceOffer>> services() async =>
      (await _get('/catalog/services')).list('data').map(ServiceOffer.fromJson).toList();
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) => AccountRepository(ref.watch(dioProvider)));
