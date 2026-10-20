import 'package:flutter_test/flutter_test.dart';
import 'package:konekt/app/router/app_router.dart';
import 'package:konekt/app/router/routes.dart';
import 'package:konekt/core/utils/countdown.dart';
import 'package:konekt/core/utils/money_format.dart';
import 'package:konekt/core/utils/relative_date.dart';
import 'package:konekt/core/utils/validators.dart';
import 'package:konekt/features/auth/domain/auth_models.dart';

void main() {
  test('formatFcfa utilise des espaces insécables', () {
    expect(formatFcfa(152400), '152 400 FCFA');
    expect(formatSignedFcfa(-50440), '− 50 440 FCFA');
    expect(formatSignedFcfa(1000), '+ 1 000 FCFA');
    expect(parseAmount('25 000'), 25000);
    expect(parseAmount(''), isNull);
  });

  test('relativeDate', () {
    final now = DateTime(2026, 10, 20, 15);
    expect(relativeDate(DateTime(2026, 10, 20, 9, 5), now: now), "Aujourd'hui à 09:05");
    expect(relativeDate(DateTime(2026, 10, 19, 22, 30), now: now), 'Hier à 22:30');
    expect(relativeDate(DateTime(2026, 8, 3, 7, 0), now: now), '3 août à 07:00');
  });

  test('mmss', () {
    expect(mmss(const Duration(minutes: 5)), '5:00');
    expect(mmss(const Duration(milliseconds: 59001)), '1:00');
    expect(mmss(const Duration(seconds: -3)), '0:00');
  });

  test('validators', () {
    expect(Validators.isCardId('121 436 474'), isTrue);
    expect(Validators.isCardId('12345'), isFalse);
    expect(Validators.containsLetterO('12O4'), isTrue);
    expect(Validators.isWeakPin('111111'), isTrue);
    expect(Validators.isWeakPin('123456'), isTrue);
    expect(Validators.isWeakPin('654321'), isTrue);
    expect(Validators.isWeakPin('482915'), isFalse);
    expect(Validators.isMsisdn('+229 01 96 66 62 62'), isTrue);
    expect(Validators.formatInviteCode('ab12cd34ef'), 'AB12-CD34');
  });

  test('authRedirect', () {
    const unauth = AuthState.unauthenticated();
    const noPin = AuthState(AuthStatus.authenticated);
    const ok = AuthState(AuthStatus.authenticated, hasPin: true);
    expect(authRedirect(const AuthState.unknown(), Routes.home), Routes.splash);
    expect(authRedirect(unauth, Routes.home), Routes.login);
    expect(authRedirect(unauth, Routes.invite), isNull);
    expect(authRedirect(noPin, Routes.home), Routes.pinSetup);
    expect(authRedirect(ok, Routes.login), Routes.home);
    expect(authRedirect(ok, Routes.splash), isNull);
    expect(authRedirect(ok, Routes.card), isNull);
  });
}
