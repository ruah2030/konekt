import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/app.dart';
import 'package:konekt/core/domain/session.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/core/storage/app_prefs.dart';
import 'package:konekt/core/storage/secure_store.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';
import 'package:konekt/features/auth/presentation/providers/auth_controller.dart';

import '../helpers/test_app.dart';

/// Stockage sécurisé illisible (ex. clés de chiffrement changées après une réinstallation).
class _BrokenStore extends InMemorySecureStore {
  @override
  Future<CardSession?> get cardSession async => throw Exception('BadPaddingException');
}

/// Stockage qui ne répond jamais.
class _HangingStore extends InMemorySecureStore {
  @override
  Future<CardSession?> get cardSession => Completer<CardSession?>().future;
}

List<Override> _overrides(TestEnv env, SecureStore store) => [
  fakeApiProvider.overrideWithValue(env.api),
  appPrefsProvider.overrideWithValue(env.prefs),
  secureStoreProvider.overrideWithValue(store),
];

void main() {
  test('stockage sécurisé illisible : on sort de l’état inconnu (pas de splash bloqué)', () async {
    final env = await TestEnv.create();
    final c = ProviderContainer(overrides: _overrides(env, _BrokenStore()));
    addTearDown(c.dispose);
    await TestEnv.waitForAuth(c);
    expect(c.read(authControllerProvider).status, AuthStatus.unauthenticated);
  });

  testWidgets('stockage qui ne répond pas : le splash finit par laisser la place', (tester) async {
    final env = await TestEnv.create();
    await tester.pumpWidget(
      ProviderScope(overrides: _overrides(env, _HangingStore()), child: const KonektApp(useGoogleFonts: false)),
    );
    expect(find.byKey(const Key('splash-logo')), findsOneWidget);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byKey(const Key('splash-logo')), findsNothing);
  });
}
