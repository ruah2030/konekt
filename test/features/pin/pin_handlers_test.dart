import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/pin/data/pin_repository.dart';

import '../../helpers/test_app.dart';

Future<ApiFailure> failureOf(Future<Object?> f) async {
  try {
    await f;
  } catch (e) {
    return ApiFailure.from(e);
  }
  fail('Une erreur était attendue');
}

void main() {
  late TestEnv env;
  late PinRepository repo;

  Future<void> setUpEnv({bool hasPin = false}) async {
    env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: hasPin));
    final container = env.container();
    addTearDown(container.dispose);
    repo = container.read(pinRepositoryProvider);
  }

  group('vérification SMS + e-mail', () {
    setUp(setUpEnv);

    test('envoie le code et renvoie les destinations masquées', () async {
      expect(await repo.requestVerification(), ['+229 •• •• •• 456', 'a•••@gmail.com']);
    });

    test('000000 → PIN_CODE_INVALID avec décompte des essais', () async {
      await repo.requestVerification();
      var f = await failureOf(repo.confirmVerification('000000'));
      expect(f.code, ErrorCodes.pinCodeInvalid);
      expect(f.message, 'Code incorrect, 2 essai(s) restant(s).');
      f = await failureOf(repo.confirmVerification('000000'));
      expect(f.message, 'Code incorrect, 1 essai(s) restant(s).');
      // La session n'est pas fermée par une erreur de code.
      expect(env.db.accessTokens, isNotEmpty);
    });

    test('code valide → verificationToken', () async {
      final token = await repo.confirmVerification('123456');
      expect(token, isNotEmpty);
      expect(env.db.pinVerificationToken, token);
    });
  });

  group('création', () {
    setUp(setUpEnv);

    test('crée le PIN avec un jeton valide', () async {
      final token = await repo.confirmVerification('123456');
      await repo.create(verificationToken: token, pin: '482915');
      expect(env.db.pin, '482915');
      final status = await repo.status();
      expect(status.hasPin, isTrue);
      expect(status.triesLeft, 5);
      expect(status.lockedUntil, isNull);
    });

    test('PIN faible → 422 PIN_TOO_WEAK', () async {
      final token = await repo.confirmVerification('123456');
      final f = await failureOf(repo.create(verificationToken: token, pin: '123456'));
      expect(f.code, ErrorCodes.pinTooWeak);
      expect(f.statusCode, 422);
      expect(env.db.pin, isNull);
    });

    test('jeton invalide → FORBIDDEN', () async {
      final f = await failureOf(repo.create(verificationToken: 'nope', pin: '482915'));
      expect(f.code, ErrorCodes.forbidden);
    });
  });

  group('contrôle et changement', () {
    setUp(() => setUpEnv(hasPin: true));

    test('check : bon PIN → OK, mauvais PIN → FORBIDDEN et décompte', () async {
      await repo.check('482915');
      final f = await failureOf(repo.check('111222'));
      expect(f.code, ErrorCodes.forbidden);
      expect(f.message, 'Code secret incorrect. 4 essai(s) avant verrouillage.');
      expect(env.db.pinTries, 4);
    });

    test('change : mauvais PIN actuel → FORBIDDEN', () async {
      final f = await failureOf(repo.change(currentPin: '000111', newPin: '135790'));
      expect(f.code, ErrorCodes.forbidden);
      expect(f.message, 'Code secret incorrect. 4 essai(s) avant verrouillage.');
      expect(env.db.pinTries, 4);
    });

    test('change : nouveau == ancien → REQUEST_REJECTED', () async {
      final f = await failureOf(repo.change(currentPin: '482915', newPin: '482915'));
      expect(f.code, ErrorCodes.requestRejected);
      expect(f.message, "Le nouveau code doit être différent de l'ancien.");
    });

    test('change : succès', () async {
      await repo.change(currentPin: '482915', newPin: '135790');
      expect(env.db.pin, '135790');
    });

    test('5 erreurs → verrouillage, puis reset le lève', () async {
      for (var i = 0; i < 5; i++) {
        await failureOf(repo.check('111222'));
      }
      expect(env.db.pinLockedUntil, isNotNull);
      final status = await repo.status();
      expect(status.isLocked(DateTime.now()), isTrue);

      final token = await repo.confirmVerification('654321');
      await repo.reset(verificationToken: token, pin: '246813');
      expect(env.db.pin, '246813');
      expect(env.db.pinTries, 5);
      expect(env.db.pinLockedUntil, isNull);
    });
  });
}
