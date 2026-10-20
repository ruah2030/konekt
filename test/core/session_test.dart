import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/features/account/data/account_repository.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';

import '../helpers/test_app.dart';

void main() {
  test('une requête sans jeton après déconnexion ne signale pas d’expiration (pas de boucle)', () async {
    final env = await TestEnv.create(signedIn: true);
    final c = env.container();
    addTearDown(c.dispose);
    c.read(authControllerProvider);
    for (var i = 0; i < 20 && c.read(authControllerProvider).status == AuthStatus.unknown; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(c.read(authControllerProvider).status, AuthStatus.authenticated);

    var expired = 0;
    c.read(sessionExpiredProvider).stream.listen((_) => expired++);
    await c.read(authControllerProvider.notifier).logout();
    expect(await env.store.accessToken, isNull);

    await expectLater(c.read(accountRepositoryProvider).me(), throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    expect(expired, 0);
    expect(c.read(authControllerProvider).status, AuthStatus.unauthenticated);
  });

  test('sessionEnded efface les jetons locaux', () async {
    final env = await TestEnv.create(signedIn: true);
    final c = env.container();
    addTearDown(c.dispose);
    c.read(authControllerProvider);
    await Future<void>.delayed(Duration.zero);
    c.read(authControllerProvider.notifier).sessionEnded();
    await Future<void>.delayed(Duration.zero);
    expect(await env.store.accessToken, isNull);
    expect(await env.store.refreshToken, isNull);
  });
}
