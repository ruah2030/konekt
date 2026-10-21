import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/card.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/network/fake/fake_api.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/core/network/fake/handlers/card_handlers.dart';
import 'package:konekt/features/card/data/card_repository.dart';

Future<ApiFailure> failureOf(Future<Object?> f) async {
  try {
    await f;
  } on Object catch (e) {
    return ApiFailure.from(e);
  }
  fail('Une erreur était attendue');
}

/// Dio branché sur le faux backend, avec un jeton de session valide.
({FakeDb db, Dio dio, CardRepository repo}) setUpWith(String status) {
  final db = FakeDb(cardStatus: status);
  final token = db.issueTokens().session;
  final dio = Dio(BaseOptions(headers: {'Authorization': 'Bearer $token', 'X-Request-Id': 'req_test'}))
    ..interceptors.add(FakeApiInterceptor(FakeApi(db: db, latency: Duration.zero)));
  return (db: db, dio: dio, repo: CardRepository(dio));
}

void main() {
  group('PATCH /cards/status', () {
    test('suspendre puis réactiver : réponse, opération à 0 et statut', () async {
      final (:db, :dio, :repo) = setUpWith('Active');
      final opsBefore = db.operations.length;
      final r = await repo.changeStatus(db.sessionCardId, CardStatus.inactive);
      expect(r.previousStatus, CardStatus.active);
      expect(r.newStatus, CardStatus.inactive);
      expect(db.cardStatus, 'Inactive');
      expect(db.operations, hasLength(opsBefore + 1));
      expect(db.operations.first['id'], r.operationId);
      expect(db.operations.first['amount'], 0);

      final raw = await dio.patch<Map<String, dynamic>>(
        '/cards/status',
        data: {'cardCustomerId': db.sessionCardId, 'newStatus': 'Active'},
      );
      expect(raw.statusCode, 200);
      expect(raw.data!.keys, containsAll(['success', 'operationId', 'previousStatus', 'newStatus']));
      expect(raw.data!['previousStatus'], 'Inactive');
      expect(db.cardStatus, 'Active');
    });

    test('même état → 400 « déjà dans l’état demandé »', () async {
      final (:db, dio: _, :repo) = setUpWith('Active');
      final f = await failureOf(repo.changeStatus(db.sessionCardId, CardStatus.active));
      expect(f.statusCode, 400);
      expect(f.code, ErrorCodes.requestRejected);
      expect(f.message, 'Cette carte est déjà dans l’état demandé.');
    });

    test('LostOrStolen sans accusé → 400 DÉFINITIVE ; avec accusé → perdue + notification SECURITY', () async {
      final (:db, dio: _, :repo) = setUpWith('Active');
      var f = await failureOf(repo.changeStatus(db.sessionCardId, CardStatus.lostOrStolen));
      expect(f.statusCode, 400);
      expect(f.message, startsWith('Cette déclaration est DÉFINITIVE'));
      expect(db.cardStatus, 'Active');

      final notifs = db.notifications.length;
      final r = await repo.changeStatus(db.sessionCardId, CardStatus.lostOrStolen, acknowledgeIrreversible: true);
      expect(r.newStatus, CardStatus.lostOrStolen);
      expect(db.cardStatus, 'LostOrStolen');
      expect(db.notifications, hasLength(notifs + 1));
      expect(db.notifications.first['kind'], 'SECURITY');

      // Terminal : plus aucune transition.
      f = await failureOf(repo.changeStatus(db.sessionCardId, CardStatus.active));
      expect(f.statusCode, 400);
      expect(f.message, contains('perdue ou volée'));
    });

    test('Inactive → LostOrStolen refusé (réactiver d’abord)', () async {
      final (:db, dio: _, :repo) = setUpWith('Inactive');
      final f = await failureOf(
        repo.changeStatus(db.sessionCardId, CardStatus.lostOrStolen, acknowledgeIrreversible: true),
      );
      expect(f.statusCode, 400);
      expect(f.message, startsWith('Cette carte est suspendue. Réactivez-la d’abord'));
      expect(db.cardStatus, 'Inactive');
    });

    test('PreActive : toute transition refusée', () async {
      final (:db, dio: _, :repo) = setUpWith('PreActive');
      for (final s in [CardStatus.active, CardStatus.inactive, CardStatus.lostOrStolen]) {
        final f = await failureOf(repo.changeStatus(db.sessionCardId, s, acknowledgeIrreversible: true));
        expect(f.statusCode, 400);
        expect(f.message, startsWith('Cette carte n’a pas encore été activée'));
      }
    });

    test('Deactivated : refusé', () async {
      final (:db, dio: _, :repo) = setUpWith('Deactivated');
      final f = await failureOf(repo.changeStatus(db.sessionCardId, CardStatus.active));
      expect(f.statusCode, 400);
      expect(f.code, ErrorCodes.requestRejected);
    });

    test('newStatus hors liste, champ inconnu → VALIDATION_FAILED ; autre carte → 403', () async {
      final (:db, :dio, repo: _) = setUpWith('Active');
      var f = await failureOf(
        dio.patch<void>('/cards/status', data: {'cardCustomerId': db.sessionCardId, 'newStatus': 'PreActive'}),
      );
      expect(f.code, ErrorCodes.validationFailed);
      f = await failureOf(
        dio.patch<void>(
          '/cards/status',
          data: {'cardCustomerId': db.sessionCardId, 'newStatus': 'Inactive', 'pin': '482915'},
        ),
      );
      expect(f.code, ErrorCodes.validationFailed);
      f = await failureOf(
        dio.patch<void>('/cards/status', data: {'cardCustomerId': '999999999', 'newStatus': 'Inactive'}),
      );
      expect(f.statusCode, 403);
    });
  });

  group('POST /cards/display/authorize', () {
    test('réponse : displayUrl, expiresAt, expiresInSeconds = 60', () async {
      final (:db, :dio, :repo) = setUpWith('Active');
      final raw = await dio.post<Map<String, dynamic>>(
        '/cards/display/authorize',
        data: {'cardCustomerId': db.sessionCardId},
      );
      expect(raw.statusCode, 200);
      expect(raw.data!['success'], isTrue);
      expect(raw.data!['expiresInSeconds'], 60);
      expect(DateTime.parse(raw.data!['expiresAt'] as String).isAfter(DateTime.now()), isTrue);
      final auth = await repo.authorizeDisplay(db.sessionCardId);
      expect(auth.displayUrl.queryParameters['t'], isNotEmpty);
      expect(isFakeCardDisplayUrl(auth.displayUrl), isTrue);
    });

    test('propriété exacte (pas de normalisation) → 403', () async {
      final (:db, dio: _, :repo) = setUpWith('Active');
      final f = await failureOf(repo.authorizeDisplay(' ${db.sessionCardId}'));
      expect(f.statusCode, 403);
      expect(f.message, 'Vous ne pouvez afficher que votre propre carte.');
    });

    test('plafond de 20 affichages par jour → 403', () async {
      final (:db, dio: _, :repo) = setUpWith('Active');
      for (var i = 0; i < fakeDisplayMaxPerCardPerDay; i++) {
        await repo.authorizeDisplay(db.sessionCardId);
      }
      final f = await failureOf(repo.authorizeDisplay(db.sessionCardId));
      expect(f.statusCode, 403);
      expect(f.code, ErrorCodes.forbidden);
      expect(f.message, 'Cette carte a été consultée trop de fois aujourd’hui. Réessayez demain.');
    });

    test('PreActive et Inactive affichables ; LostOrStolen bloqué', () async {
      for (final s in ['PreActive', 'Inactive']) {
        final (:db, dio: _, :repo) = setUpWith(s);
        expect((await repo.authorizeDisplay(db.sessionCardId)).expiresInSeconds, 60);
      }
      final (:db, dio: _, :repo) = setUpWith('LostOrStolen');
      final f = await failureOf(repo.authorizeDisplay(db.sessionCardId));
      expect(f.statusCode, 403);
      expect(f.message, 'Les données de cette carte ne peuvent plus être affichées : elle a été bloquée.');
    });

    test('champ inconnu → VALIDATION_FAILED', () async {
      final (:db, :dio, repo: _) = setUpWith('Active');
      final f = await failureOf(
        dio.post<void>('/cards/display/authorize', data: {'cardCustomerId': db.sessionCardId, 'pin': '1'}),
      );
      expect(f.code, ErrorCodes.validationFailed);
    });
  });
}
