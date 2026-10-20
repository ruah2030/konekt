import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/pin/domain/pin_flow.dart';
import 'package:konekt/features/pin/presentation/providers/pin_flow_controller.dart';

import '../../helpers/test_app.dart';

void main() {
  late TestEnv env;
  late ProviderContainer container;

  Future<PinFlowController> start(PinFlow flow, {bool hasPin = false}) async {
    env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: hasPin));
    container = env.container();
    addTearDown(container.dispose);
    container.listen(pinFlowControllerProvider(flow), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    return container.read(pinFlowControllerProvider(flow).notifier);
  }

  PinFlowState stateOf(PinFlow flow) => container.read(pinFlowControllerProvider(flow));

  test('setup : vérification → nouveau → confirmation → PIN créé', () async {
    final c = await start(PinFlow.setup);
    expect(stateOf(PinFlow.setup).step, isA<PinVerifyStep>());
    expect(stateOf(PinFlow.setup).obscure, isFalse);

    await c.submit('123456');
    expect(stateOf(PinFlow.setup).step, isA<PinNewStep>());
    expect(stateOf(PinFlow.setup).obscure, isTrue);

    await c.submit('482915');
    expect(stateOf(PinFlow.setup).step, isA<PinConfirmStep>());

    await c.submit('482915');
    expect(stateOf(PinFlow.setup).isDone, isTrue);
    expect(env.db.pin, '482915');
  });

  test('setup : code de vérification erroné → erreur et saisie vidée', () async {
    final c = await start(PinFlow.setup);
    c.setCode('000000');
    await c.submit('000000');
    final s = stateOf(PinFlow.setup);
    expect(s.step, isA<PinVerifyStep>());
    expect(s.code, isEmpty);
    expect(s.error?.code, ErrorCodes.pinCodeInvalid);
    expect(s.error?.message, 'Code incorrect, 2 essai(s) restant(s).');
  });

  test('PIN faible refusé (PIN_TOO_WEAK)', () async {
    final c = await start(PinFlow.setup);
    await c.submit('123456');
    for (final weak in ['111111', '123456', '987654']) {
      await c.submit(weak);
      final s = stateOf(PinFlow.setup);
      expect(s.step, isA<PinNewStep>());
      expect(s.error?.code, ErrorCodes.pinTooWeak);
    }
  });

  test('confirmation différente → retour au nouveau code avec erreur', () async {
    final c = await start(PinFlow.setup);
    await c.submit('123456');
    await c.submit('482915');
    await c.submit('482916');
    final s = stateOf(PinFlow.setup);
    expect(s.step, isA<PinNewStep>());
    expect(s.error?.code, ErrorCodes.validationFailed);
    expect(s.error?.message, 'Les deux codes ne correspondent pas. Recommencez.');
    expect(env.db.pin, isNull);
  });

  test('retour : confirmation → nouveau code ; sinon quitte l’écran', () async {
    final c = await start(PinFlow.setup);
    expect(c.back(), isFalse);
    await c.submit('123456');
    await c.submit('482915');
    expect(c.back(), isTrue);
    expect(stateOf(PinFlow.setup).step, isA<PinNewStep>());
  });

  test('change : ancien PIN vérifié côté serveur, nouveau ≠ ancien, confirmation', () async {
    final c = await start(PinFlow.change, hasPin: true);
    expect(stateOf(PinFlow.change).step, isA<PinOldStep>());

    await c.submit('111222');
    expect(stateOf(PinFlow.change).step, isA<PinOldStep>());
    expect(stateOf(PinFlow.change).error?.message, 'Code secret incorrect. 4 essai(s) avant verrouillage.');

    await c.submit('482915');
    expect(stateOf(PinFlow.change).step, isA<PinNewStep>());

    await c.submit('482915');
    expect(stateOf(PinFlow.change).error?.message, "Le nouveau code doit être différent de l'ancien.");

    await c.submit('135790');
    await c.submit('135790');
    expect(stateOf(PinFlow.change).isDone, isTrue);
    expect(env.db.pin, '135790');
  });

  test('reset : vérification → nouveau → confirmation, lève le verrouillage', () async {
    final c = await start(PinFlow.reset, hasPin: true);
    env.db
      ..pinTries = 1
      ..pinLockedUntil = DateTime.now().add(const Duration(minutes: 10));
    await c.submit('654321');
    await c.submit('246813');
    await c.submit('246813');
    expect(stateOf(PinFlow.reset).isDone, isTrue);
    expect(env.db.pin, '246813');
    expect(env.db.pinTries, 5);
    expect(env.db.pinLockedUntil, isNull);
  });
}
