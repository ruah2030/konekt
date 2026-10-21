import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/core/network/fake/fake_api.dart';
import 'package:konekt/features/account/data/account_repository.dart';
import 'package:konekt/features/auth/data/auth_repository.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';

import '../helpers/test_app.dart';

void main() {
  test('connexion complète : channels → login/init → login/confirm', () async {
    final env = await TestEnv.create();
    final c = env.container();
    addTearDown(c.dispose);
    final repo = c.read(authRepositoryProvider);
    final channels = await repo.channels();
    expect(channels.isAvailable(OtpChannel.sms), isTrue);
    expect(channels.isAvailable(OtpChannel.whatsapp), isFalse);
    final challenge = await repo.loginInit(cardId: '121 436 474', last4: '4589', channel: OtpChannel.sms);
    expect(challenge.cardCustomerId, '121436474');
    expect(challenge.maskedContacts, ['+229****456']);
    final session = await repo.loginConfirm(challenge, '482910');
    expect(session.cardCustomerId, '121436474');
    expect(session.hasPin, isFalse);
    expect(await env.store.sessionToken, isNotNull);
  });

  test('erreur au format API : code, message, details, requestId', () async {
    final env = await TestEnv.create();
    final c = env.container();
    addTearDown(c.dispose);
    final failure = await c
        .read(authRepositoryProvider)
        .loginInit(cardId: '121436474', last4: '12')
        .then<ApiFailure?>((_) => null, onError: (Object e) => ApiFailure.from(e));
    expect(failure!.code, ErrorCodes.validationFailed);
    expect(failure.fieldErrors('last4Digits'), ['Quatre chiffres attendus.']);
    expect(failure.ref, startsWith('req_'));
  });

  test('SESSION_EXPIRED : refresh puis rejeu transparent', () async {
    final env = await TestEnv.create(signedIn: true);
    final c = env.container();
    addTearDown(c.dispose);
    await TestEnv.waitForAuth(c);
    // Le jeton de session est révoqué côté serveur, le refresh token reste valable.
    env.db.revokeSessionToken(await env.store.sessionToken);
    final card = await c.read(accountRepositoryProvider).card('121436474');
    expect(card.last4, '4589');
    expect(c.read(authControllerProvider).status, AuthStatus.authenticated);
  });

  test('refresh impossible → déconnexion et jetons effacés', () async {
    final env = await TestEnv.create(signedIn: true);
    final c = env.container();
    addTearDown(c.dispose);
    await TestEnv.waitForAuth(c);
    env.db.revokeAll();
    await expectLater(c.read(accountRepositoryProvider).card('121436474'), throwsA(isA<DioException>()));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(await env.store.sessionToken, isNull);
  });

  test('une requête sans jeton après déconnexion ne signale pas d’expiration (pas de boucle)', () async {
    final env = await TestEnv.create(signedIn: true);
    final c = env.container();
    addTearDown(c.dispose);
    await TestEnv.waitForAuth(c);
    expect(c.read(authControllerProvider).status, AuthStatus.authenticated);
    var expired = 0;
    c.read(sessionExpiredProvider).stream.listen((_) => expired++);
    await c.read(authControllerProvider.notifier).logout();
    expect(await env.store.sessionToken, isNull);
    await expectLater(c.read(accountRepositoryProvider).card('121436474'), throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    expect(expired, 0);
  });

  test('« Jeton non reconnu pour cette route » ne déconnecte pas', () async {
    final env = await TestEnv.create(signedIn: true);
    env.api.on(
      'GET',
      '/operations/summary',
      (_) => FakeResponse.error(401, 'UNAUTHENTICATED', 'Jeton non reconnu pour cette route. Reconnectez-vous.'),
    );
    final c = env.container();
    addTearDown(c.dispose);
    await TestEnv.waitForAuth(c);
    await expectLater(c.read(dioProvider).get<Object>('/operations/summary'), throwsA(isA<DioException>()));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(authControllerProvider).status, AuthStatus.authenticated);
  });

  test('relevé, opérations et notifications au format API', () async {
    final env = await TestEnv.create(signedIn: true);
    final c = env.container();
    addTearDown(c.dispose);
    await TestEnv.waitForAuth(c);
    final repo = c.read(accountRepositoryProvider);
    expect(await repo.balance('121436474'), 152400);
    final txs = await repo.transactions('121436474');
    expect(txs.first.amount, -50440);
    final ops = await repo.operations(cardCustomerId: '121436474');
    expect(ops.items.first.counterparty, 'Afiavi Sossou · •••• 9034');
    final notifs = await repo.notifications();
    expect(notifs.unreadCount, 2);
    expect(await repo.unreadCount(), 2);
  });
}
