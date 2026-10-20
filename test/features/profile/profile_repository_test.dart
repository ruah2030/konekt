import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/features/profile/data/profile_repository.dart';
import 'package:konekt/features/profile/domain/profile_models.dart';

import '../../helpers/test_app.dart';

void main() {
  late TestEnv env;
  late ProfileRepository repo;

  setUp(() async {
    env = await TestEnv.create(signedIn: true);
    repo = env.container().read(profileRepositoryProvider);
  });

  test('préférences : lecture et écriture (y compris Auto = null)', () async {
    expect(await repo.channelPreference(), MessageChannel.sms);
    await repo.setChannelPreference(MessageChannel.whatsapp);
    expect(env.db.channelPreference, 'WHATSAPP');
    await repo.setChannelPreference(MessageChannel.auto);
    expect(env.db.channelPreference, isNull);
    expect(await repo.channelPreference(), MessageChannel.auto);
  });

  test('appareils : liste puis déconnexion d’un appareil non courant', () async {
    final devices = await repo.devices();
    expect(devices.map((d) => d.platform), [DevicePlatform.android, DevicePlatform.ios, DevicePlatform.web]);
    expect(devices.first.current, isTrue);
    await repo.removeDevice('dv2');
    expect(env.db.devices.map((d) => d['id']), ['dv_current', 'dv3']);
    expect(env.db.accessTokens, isNotEmpty);
  });

  test('déconnecter l’appareil courant révoque le jeton appelant', () async {
    expect(env.db.accessTokens, hasLength(1));
    await repo.removeDevice('dv_current');
    expect(env.db.accessTokens, isEmpty);
  });

  test('appareil inconnu → 404', () async {
    try {
      await repo.removeDevice('nope');
      fail('404 attendu');
    } on Object catch (e) {
      expect(ApiFailure.from(e).code, ErrorCodes.notFound);
    }
  });

  test('jeton push enregistré', () async {
    await repo.registerPushToken(token: 'fcm_123', platform: DevicePlatform.android);
    expect(env.db.pushToken, 'fcm_123');
  });
}
