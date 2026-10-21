import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/network/dio_client.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/pin/data/pin_repository.dart';
import 'package:konekt/features/pin/domain/pin_flow.dart';
import 'package:konekt/features/pin/domain/pin_rules.dart';
import 'package:konekt/features/pin/presentation/providers/pin_flow_controller.dart';

import '../../helpers/test_app.dart';

/// Refuse une seule fois le PIN (`PIN_TOO_WEAK`, comme si le serveur avait une règle de plus)
/// et mémorise les codes reçus.
class _StrictServerRepo extends PinRepository {
  _StrictServerRepo(super.dio);
  final codes = <String>[];
  bool refused = false;

  @override
  Future<void> create({required String pin, required String code}) {
    codes.add(code);
    if (!refused) {
      refused = true;
      throw const ApiFailure(code: ErrorCodes.pinTooWeak, message: 'Code secret trop simple.', statusCode: 400);
    }
    return super.create(pin: pin, code: code);
  }
}

Future<void> flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  Future<(TestEnv, ProviderContainer, PinFlowController)> start(
    PinFlow flow, {
    bool hasPin = false,
    PinRepository Function(Dio dio)? repo,
  }) async {
    final env = await TestEnv.create(signedIn: true, db: FakeDb(hasPin: hasPin));
    final container = ProviderContainer(
      overrides: [
        ...env.overrides,
        if (repo != null) pinRepositoryProvider.overrideWith((ref) => repo(ref.watch(dioProvider))),
      ],
    );
    addTearDown(container.dispose);
    container.listen(pinFlowControllerProvider(flow), (_, _) {});
    await flush();
    return (env, container, container.read(pinFlowControllerProvider(flow).notifier));
  }

  PinFlowState stateOf(ProviderContainer c, PinFlow flow) => c.read(pinFlowControllerProvider(flow));

  test('règles locales du PIN (§7.4)', () {
    expect(PinRules.problem('111111'), PinRules.repeatedMessage);
    expect(PinRules.problem('345678'), PinRules.sequenceMessage);
    expect(PinRules.problem('987654'), PinRules.sequenceMessage);
    expect(PinRules.problem('12345'), PinRules.formatMessage);
    expect(PinRules.problem('482915'), isNull);
  });

  test('création : code demandé au début, saisi localement, puis POST pin', () async {
    final (env, c, ctrl) = await start(PinFlow.setup);
    var s = stateOf(c, PinFlow.setup);
    expect(s.step, isA<PinCodeStep>());
    expect(s.sent?.maskedContacts, [env.db.maskedPhone, env.db.maskedEmail]);
    expect(s.sent?.expiryMinutes, 5);
    expect(s.obscure, isFalse);

    await ctrl.submit('604218');
    expect(stateOf(c, PinFlow.setup).step, isA<PinNewStep>());
    expect(env.db.pinCode?['attemptsLeft'], 3, reason: "le code n'est pas envoyé seul");

    await ctrl.submit('111111');
    s = stateOf(c, PinFlow.setup);
    expect(s.step, isA<PinNewStep>());
    expect(s.error?.message, PinRules.repeatedMessage);

    await ctrl.submit('482915');
    await ctrl.submit('482910');
    s = stateOf(c, PinFlow.setup);
    expect(s.step, isA<PinNewStep>());
    expect(s.error?.message, PinFlowController.mismatchMessage);

    await ctrl.submit('482915');
    await ctrl.submit('482915');
    expect(stateOf(c, PinFlow.setup).step, isA<PinDoneStep>());
    expect(env.db.pin, '482915');
  });

  test('création : PIN_TOO_WEAK du serveur → retour au nouveau PIN, code reçu conservé', () async {
    late _StrictServerRepo spy;
    final (env, c, ctrl) = await start(PinFlow.setup, repo: (dio) => spy = _StrictServerRepo(dio));
    await ctrl.submit('604218');
    await ctrl.submit('482915');
    await ctrl.submit('482915');
    final s = stateOf(c, PinFlow.setup);
    expect(s.step, isA<PinNewStep>());
    expect(s.error?.code, ErrorCodes.pinTooWeak);

    await ctrl.submit('730519');
    await ctrl.submit('730519');
    expect(stateOf(c, PinFlow.setup).step, isA<PinDoneStep>());
    expect(spy.codes, ['604218', '604218']);
    expect(env.db.pin, '730519');
  });

  test('création : code faux → retour à l’étape code avec les essais restants', () async {
    final (env, c, ctrl) = await start(PinFlow.setup);
    await ctrl.submit('000000');
    await ctrl.submit('482915');
    await ctrl.submit('482915');
    final s = stateOf(c, PinFlow.setup);
    expect(s.step, isA<PinCodeStep>());
    expect(s.error?.message, 'Code incorrect, 2 essai(s) restant(s).');
    expect(env.db.pin, isNull);

    await ctrl.submit('604218');
    await ctrl.submit('482915');
    await ctrl.submit('482915');
    expect(stateOf(c, PinFlow.setup).step, isA<PinDoneStep>());
  });

  test('création : code expiré → nouveau code demandé automatiquement', () async {
    final (env, c, ctrl) = await start(PinFlow.setup);
    env.db.pinCode!['expiresAt'] = DateTime.now().subtract(const Duration(seconds: 1));
    await ctrl.submit('604218');
    await ctrl.submit('482915');
    await ctrl.submit('482915');
    await flush();
    final s = stateOf(c, PinFlow.setup);
    expect(s.step, isA<PinCodeStep>());
    expect(s.error?.code, ErrorCodes.pinCodeExpired);
    expect(s.error?.message, endsWith(PinFlowController.newCodeSentSuffix));
    expect(env.db.now().isBefore(env.db.pinCode!['expiresAt'] as DateTime), isTrue);
  });

  test('création : PIN déjà défini → terminé', () async {
    final (_, c, _) = await start(PinFlow.setup, hasPin: true);
    final step = stateOf(c, PinFlow.setup).step;
    expect(step, isA<PinDoneStep>());
    expect((step as PinDoneStep).alreadyDefined, isTrue);
  });

  test('changement : 403 → retour au PIN actuel ; 400 → retour au nouveau PIN', () async {
    final (env, c, ctrl) = await start(PinFlow.change, hasPin: true);
    expect(stateOf(c, PinFlow.change).step, isA<PinCurrentStep>());

    await ctrl.submit('111222');
    await ctrl.submit('135790');
    await ctrl.submit('135790');
    var s = stateOf(c, PinFlow.change);
    expect(s.step, isA<PinCurrentStep>());
    expect(s.error?.message, 'Code secret incorrect — 4 tentative(s) restante(s).');

    await ctrl.submit('482915');
    await ctrl.submit('482915');
    s = stateOf(c, PinFlow.change);
    expect(s.step, isA<PinNewStep>());
    expect(s.error?.message, PinFlowController.sameAsOldMessage);

    await ctrl.submit('135790');
    await ctrl.submit('135790');
    expect(stateOf(c, PinFlow.change).step, isA<PinDoneStep>());
    expect(env.db.pin, '135790');
  });

  test('oubli : reset/request → code → nouveau PIN → reset/confirm', () async {
    final (env, c, ctrl) = await start(PinFlow.reset, hasPin: true);
    env.db.pinLockedUntil = DateTime.now().add(const Duration(minutes: 10));
    expect(env.db.pinCode?['purpose'], 'reset');
    await ctrl.submit('604218');
    await ctrl.submit('135790');
    await ctrl.submit('135790');
    expect(stateOf(c, PinFlow.reset).step, isA<PinDoneStep>());
    expect(env.db.pin, '135790');
    expect(env.db.pinLockedUntil, isNull);
  });
}
