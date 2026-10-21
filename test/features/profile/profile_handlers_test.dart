import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/core/network/api_failure.dart';
import 'package:konekt/core/network/fake/fake_api.dart';
import 'package:konekt/core/network/fake/fake_db.dart';
import 'package:konekt/features/profile/data/profile_repository.dart';
import 'package:konekt/features/profile/domain/profile_models.dart';

Future<ApiFailure> failureOf(Future<Object?> f) async {
  try {
    await f;
  } on Object catch (e) {
    return ApiFailure.from(e);
  }
  fail('Une erreur était attendue');
}

void main() {
  late FakeDb db;
  late String token;
  late Dio dio;
  late ProfileRepository repo;

  setUp(() {
    db = FakeDb();
    token = db.issueTokens().session;
    dio = Dio(BaseOptions(headers: {'Authorization': 'Bearer $token', 'X-Request-Id': 'req_test'}))
      ..interceptors.add(FakeApiInterceptor(FakeApi(db: db, latency: Duration.zero)));
    repo = ProfileRepository(dio);
  });

  group('préférences', () {
    test('lecture et écriture, Auto = null', () async {
      expect(await repo.preferredChannel(), MessageChannel.sms);
      expect(await repo.setPreferredChannel(MessageChannel.whatsapp), MessageChannel.whatsapp);
      expect(db.preferredChannel, 'WHATSAPP');
      expect(await repo.setPreferredChannel(MessageChannel.auto), MessageChannel.auto);
      expect(db.preferredChannel, isNull);
      expect(await repo.preferredChannel(), MessageChannel.auto);
    });

    test('champ absent : rien ne change ; valeur invalide → VALIDATION_FAILED', () async {
      await dio.patch<void>('/auth/customer/preferences', data: <String, dynamic>{});
      expect(db.preferredChannel, 'SMS');
      final f = await failureOf(dio.patch<void>('/auth/customer/preferences', data: {'preferredChannel': 'PIGEON'}));
      expect(f.code, ErrorCodes.validationFailed);
    });

    test('carte externe → 409', () async {
      db.isExternalCard = true;
      final f = await failureOf(repo.setPreferredChannel(MessageChannel.email));
      expect(f.statusCode, 409);
      expect(f.code, ErrorCodes.conflict);
    });
  });

  group('appareils', () {
    test('liste au format API', () async {
      final devices = await repo.devices();
      expect(devices.map((d) => d.type), [DeviceType.android, DeviceType.ios, DeviceType.web]);
      expect(devices.first.isCurrent, isTrue);
      expect(devices.first.lastIpAddress, isNotNull);
      expect(devices.first.firstSeenAt, isNotNull);
      expect(devices.last.hasActiveSession, isFalse);
    });

    test('déconnexion d’un appareil non courant : session gardée', () async {
      final r = await repo.disconnectDevice('cldev_iphone');
      expect(r.deviceId, 'cldev_iphone');
      expect(r.closedSessions, 1);
      expect(db.devices.firstWhere((d) => d['deviceId'] == 'cldev_iphone')['hasActiveSession'], isFalse);
      expect(db.isValidSessionToken(token), isTrue);
    });

    test('déconnexion de l’appareil courant : jeton appelant révoqué', () async {
      await repo.disconnectDevice('cldev_current');
      expect(db.isValidSessionToken(token), isFalse);
      final f = await failureOf(repo.devices());
      expect(f.code, ErrorCodes.sessionExpired);
    });

    test('appareil inconnu → 404', () async {
      final f = await failureOf(repo.disconnectDevice('nope'));
      expect(f.code, ErrorCodes.notFound);
    });

    test('jeton push enregistré ; 403 sans appareil de session ; > 512 refusé', () async {
      await repo.registerPushToken('fcm_123');
      expect(db.pushToken, 'fcm_123');
      var f = await failureOf(repo.registerPushToken('x' * 513));
      expect(f.code, ErrorCodes.validationFailed);
      db.devices.removeWhere((d) => d['isCurrent'] == true);
      f = await failureOf(repo.registerPushToken('fcm_456'));
      expect(f.statusCode, 403);
    });
  });
}
