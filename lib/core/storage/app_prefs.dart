import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences non sensibles. Initialisé dans `bootstrap` puis injecté par override.
class AppPrefs {
  AppPrefs(this._p);
  final SharedPreferences _p;

  static const _firstLaunchDone = 'first_launch_done';
  static const _hideBalance = 'hide_balance';
  static const _dismissedPromos = 'dismissed_promos';

  bool get firstLaunchDone => _p.getBool(_firstLaunchDone) ?? false;
  Future<void> setFirstLaunchDone() => _p.setBool(_firstLaunchDone, true);

  bool get hideBalance => _p.getBool(_hideBalance) ?? false;
  Future<void> setHideBalance(bool v) => _p.setBool(_hideBalance, v);

  /// Code d'invitation marchand (transmis à `login/confirm` comme `merchantReferralCode`).
  static const _referralCode = 'merchant_referral_code';
  String? get referralCode => _p.getString(_referralCode);
  Future<void> setReferralCode(String? code) =>
      code == null ? _p.remove(_referralCode) : _p.setString(_referralCode, code);

  /// Faux backend uniquement : code secret de démo conservé entre deux lancements.
  static const _fakePin = 'fake_backend_pin';
  String? get fakePin => _p.getString(_fakePin);
  Future<void> setFakePin(String? pin) => pin == null ? _p.remove(_fakePin) : _p.setString(_fakePin, pin);

  List<String> get dismissedPromos => _p.getStringList(_dismissedPromos) ?? const [];
  Future<void> setDismissedPromos(List<String> ids) => _p.setStringList(_dismissedPromos, ids);
}

final appPrefsProvider = Provider<AppPrefs>(
  (ref) => throw UnimplementedError('appPrefsProvider doit être surchargé dans bootstrap'),
);
