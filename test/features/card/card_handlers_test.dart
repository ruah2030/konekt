import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/domain/card.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/card/data/card_repository.dart';

import '../../helpers/test_app.dart';

Future<ApiFailure> failureOf(Future<Object?> f) async {
  try {
    await f;
  } on Object catch (e) {
    return ApiFailure.from(e);
  }
  fail('Une erreur était attendue');
}

void main() {
  late TestEnv env;
  late CardRepository repo;

  Future<void> setUpWith(String status) async {
    env = await TestEnv.create(signedIn: true, db: FakeDb(cardStatus: status));
    repo = env.container().read(cardRepositoryProvider);
  }

  test('suspendre puis réactiver', () async {
    await setUpWith('ACTIVE');
    expect((await repo.suspend()).status, CardStatus.inactive);
    expect(env.db.cardStatus, 'INACTIVE');
    expect((await repo.reactivate()).status, CardStatus.active);
    expect(env.db.cardStatus, 'ACTIVE');
  });

  test('transitions invalides → 422 REQUEST_REJECTED', () async {
    await setUpWith('ACTIVE');
    var f = await failureOf(repo.reactivate());
    expect(f.code, ErrorCodes.requestRejected);
    expect(f.statusCode, 422);
    expect(f.message, isNotEmpty);

    await setUpWith('INACTIVE');
    f = await failureOf(repo.suspend());
    expect(f.code, ErrorCodes.requestRejected);

    await setUpWith('LOST_OR_STOLEN');
    expect((await failureOf(repo.reactivate())).code, ErrorCodes.requestRejected);
    expect((await failureOf(repo.suspend())).code, ErrorCodes.requestRejected);
    expect((await failureOf(repo.declareLost())).code, ErrorCodes.requestRejected);
  });

  test('perte/vol : définitif + notification « Carte bloquée »', () async {
    await setUpWith('INACTIVE');
    final before = env.db.notifications.length;
    expect((await repo.declareLost()).status, CardStatus.lostOrStolen);
    expect(env.db.cardStatus, 'LOST_OR_STOLEN');
    expect(env.db.notifications.length, before + 1);
    expect(env.db.notifications.first['title'], 'Carte bloquée');
  });

  test('affichage sécurisé : données valables 60 s si la carte est active', () async {
    await setUpWith('ACTIVE');
    final d = await repo.sensitiveDisplay();
    expect(d.pan, '4532 1180 7741 ${env.db.last4}');
    expect(d.expiry, '04/27');
    expect(d.cvv, '318');
    final left = d.expiresAt.difference(DateTime.now());
    expect(left.inSeconds, inInclusiveRange(55, 60));
    expect(d.toString(), isNot(contains('318')));
  });

  test('affichage sécurisé refusé si la carte n’est pas active (403 FORBIDDEN)', () async {
    for (final s in ['INACTIVE', 'PRE_ACTIVE', 'LOST_OR_STOLEN']) {
      await setUpWith(s);
      final f = await failureOf(repo.sensitiveDisplay());
      expect(f.code, ErrorCodes.forbidden);
      expect(f.statusCode, 403);
      expect(f.message, CardStatus.fromApi(s).blockedMessage);
    }
  });

  test('sans session → 401', () async {
    env = await TestEnv.create(db: FakeDb());
    final f = await failureOf(env.container().read(cardRepositoryProvider).suspend());
    expect(f, isA<ApiFailure>());
    expect(env.db.cardStatus, 'ACTIVE');
  });
}
