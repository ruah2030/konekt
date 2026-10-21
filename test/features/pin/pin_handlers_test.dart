import 'package:dio/dio.dart';
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

  group('création (§2.7.1)', () {
    setUp(setUpEnv);

    test('setup/request : contacts masqués, validité, code stocké', () async {
      final sent = await repo.requestSetupCode();
      expect(sent.channelsUsed, ['SMS', 'EMAIL']);
      expect(sent.maskedContacts, [env.db.maskedPhone, env.db.maskedEmail]);
      expect(sent.expiryMinutes, 5);
      expect(sent.destinationLabel, '${env.db.maskedPhone} et ${env.db.maskedEmail}');
      expect(env.db.pinCode?['purpose'], 'setup');
      expect(env.db.pinCode?['attemptsLeft'], 3);
    });

    test('PIN faible : PIN_TOO_WEAK sans consommer le code', () async {
      await repo.requestSetupCode();
      final f = await failureOf(repo.create(pin: '123456', code: '604218'));
      expect(f.code, ErrorCodes.pinTooWeak);
      expect(env.db.pinCode?['attemptsLeft'], 3);
      await repo.create(pin: '482915', code: '604218');
      expect(env.db.pin, '482915');
      expect(env.db.pinCode?['used'], isTrue);
    });

    test('code faux : PIN_CODE_INVALID (attemptsLeft) puis PIN_CODE_EXHAUSTED', () async {
      await repo.requestSetupCode();
      var f = await failureOf(repo.create(pin: '482915', code: '000000'));
      expect(f.code, ErrorCodes.pinCodeInvalid);
      expect(f.details['attemptsLeft'], 2);
      f = await failureOf(repo.create(pin: '482915', code: '000000'));
      expect(f.details['attemptsLeft'], 1);
      f = await failureOf(repo.create(pin: '482915', code: '000000'));
      expect(f.code, ErrorCodes.pinCodeExhausted);
      f = await failureOf(repo.create(pin: '482915', code: '604218'));
      expect(f.code, ErrorCodes.pinCodeExhausted);
    });

    test('code expiré, déjà utilisé, puis PIN_ALREADY_DEFINED', () async {
      await repo.requestSetupCode();
      env.db.pinCode!['expiresAt'] = DateTime.now().subtract(const Duration(seconds: 1));
      expect((await failureOf(repo.create(pin: '482915', code: '604218'))).code, ErrorCodes.pinCodeExpired);

      await repo.requestSetupCode();
      await repo.create(pin: '482915', code: '604218');
      env.db.pin = null;
      expect((await failureOf(repo.create(pin: '482915', code: '604218'))).code, ErrorCodes.pinCodeAlreadyUsed);

      env.db.pin = '482915';
      expect((await failureOf(repo.requestSetupCode())).code, ErrorCodes.pinAlreadyDefined);
      expect((await failureOf(repo.create(pin: '135790', code: '604218'))).code, ErrorCodes.pinAlreadyDefined);
    });

    test('5 demandes de code par minute au plus', () async {
      for (var i = 0; i < 5; i++) {
        await repo.requestSetupCode();
      }
      expect((await failureOf(repo.requestSetupCode())).code, ErrorCodes.pinCodeRateLimited);
    });

    test('code mal formé : VALIDATION_FAILED sur details.code', () async {
      final f = await failureOf(repo.create(pin: '482915', code: '12'));
      expect(f.code, ErrorCodes.validationFailed);
      expect(f.fieldErrors('code'), isNotEmpty);
    });
  });

  group('changement (§2.7.2)', () {
    setUp(() => setUpEnv(hasPin: true));

    test('succès', () async {
      await repo.change(currentPin: '482915', pin: '135790');
      expect(env.db.pin, '135790');
    });

    test('ancien PIN faux : 403 décompté, verrou de 15 min à 0', () async {
      var f = await failureOf(repo.change(currentPin: '111222', pin: '135790'));
      expect(f.statusCode, 403);
      expect(f.code, ErrorCodes.forbidden);
      expect(f.message, 'Code secret incorrect — 4 tentative(s) restante(s).');
      for (var i = 0; i < 3; i++) {
        await failureOf(repo.change(currentPin: '111222', pin: '135790'));
      }
      f = await failureOf(repo.change(currentPin: '111222', pin: '135790'));
      expect(f.message, 'Trop de codes erronés. Réessayez dans 15 minute(s), ou réinitialisez votre code.');
      expect(env.db.pinLockedUntil, isNotNull);
      // Même avec le bon PIN, le verrou refuse.
      f = await failureOf(repo.change(currentPin: '482915', pin: '135790'));
      expect(f.statusCode, 403);
    });

    test('nouveau PIN trop simple ou identique : 400', () async {
      expect((await failureOf(repo.change(currentPin: '482915', pin: '111111'))).code, ErrorCodes.pinTooWeak);
      final f = await failureOf(repo.change(currentPin: '482915', pin: '482915'));
      expect(f.statusCode, 400);
      expect(f.code, ErrorCodes.requestRejected);
      expect(f.message, "Le nouveau code doit être différent de l'ancien.");
    });
  });

  group('oubli (§2.7.3)', () {
    setUp(() => setUpEnv(hasPin: true));

    test('reset/request puis reset/confirm lève le verrou', () async {
      env.db
        ..pinAttemptsLeft = 0
        ..pinLockedUntil = DateTime.now().add(const Duration(minutes: 15));
      final sent = await repo.requestResetCode();
      expect(sent.expiryMinutes, 5);
      expect(env.db.pinCode?['purpose'], 'reset');
      expect((await failureOf(repo.confirmReset(code: '000000', pin: '135790'))).code, ErrorCodes.pinCodeInvalid);
      await repo.confirmReset(code: '604218', pin: '135790');
      expect(env.db.pin, '135790');
      expect(env.db.pinLockedUntil, isNull);
      expect(env.db.pinAttemptsLeft, 5);
    });

    test('un code de création ne vaut pas pour la réinitialisation', () async {
      env.db.pinCode = {
        'purpose': 'setup',
        'expiresAt': DateTime.now().add(const Duration(minutes: 5)),
        'attemptsLeft': 3,
        'used': false,
      };
      expect((await failureOf(repo.confirmReset(code: '604218', pin: '135790'))).code, ErrorCodes.pinCodeExpired);
    });
  });

  test('champ inconnu refusé (VALIDATION_FAILED)', () async {
    await setUpEnv(hasPin: true);
    final res = await env.api.handle(
      RequestOptions(
        path: '/auth/customer/pin/change',
        method: 'POST',
        data: {'currentPin': '482915', 'newPin': '135790'},
        headers: {'Authorization': 'Bearer ${await env.store.sessionToken}'},
      ),
    );
    expect(res.status, 400);
    expect((res.body! as Map)['code'], ErrorCodes.validationFailed);
  });
}
