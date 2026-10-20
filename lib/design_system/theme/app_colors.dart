import 'package:flutter/material.dart';

/// Palette Konekt (maquette « Card Konekt Material »).
abstract final class KColors {
  static const primary = Color(0xFF140A72);
  static const onPrimary = Color(0xFFFFFFFF);
  static const secondary = Color(0xFFF0B23A);
  static const secondaryContainer = Color(0xFFFFF4D6);
  static const onSecondaryContainer = Color(0xFF8A5300);
  static const tertiary = Color(0xFF3B63F0);
  static const primaryContainer = Color(0xFFEEF0FF);
  static const error = Color(0xFFDC2B2B);
  static const errorContainer = Color(0xFFFDECEC);
  static const onErrorContainer = Color(0xFFB91C1C);
  static const success = Color(0xFF1FA54E);
  static const successDark = Color(0xFF14843D);
  static const successContainer = Color(0xFFE5F6EB);
  static const warning = Color(0xFFF97316);
  static const warningDark = Color(0xFFC2410C);
  static const warningContainer = Color(0xFFFFF0E6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceContainer = Color(0xFFF1F2F8);
  static const background = Color(0xFFF4F5FA);
  static const fieldFill = Color(0xFFF6F7FB);
  static const onSurfaceVariant = Color(0xFF64748B);
  static const outline = Color(0xFF94A3B8);
  static const outlineVariant = Color(0xFFE2E8F0);
  static const divider = Color(0xFFF1F2F8);
  static const navIndicator = Color(0xFFFCE68A);
  static const infoContainer = Color(0xFFEAF0FF);
  static const info = Color(0xFF2C4BC4);
  static const splashTop = Color(0xFF140A72);
  static const splashBottom = Color(0xFF0B1233);
  static const deviceFrame = Color(0xFF05051A);
}

/// Extension de thème pour les couleurs hors ColorScheme M3.
@immutable
class KonektColors extends ThemeExtension<KonektColors> {
  const KonektColors({
    this.success = KColors.success,
    this.successContainer = KColors.successContainer,
    this.warning = KColors.warning,
    this.warningContainer = KColors.warningContainer,
  });

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;

  @override
  KonektColors copyWith({Color? success, Color? successContainer, Color? warning, Color? warningContainer}) =>
      KonektColors(
        success: success ?? this.success,
        successContainer: successContainer ?? this.successContainer,
        warning: warning ?? this.warning,
        warningContainer: warningContainer ?? this.warningContainer,
      );

  @override
  KonektColors lerp(ThemeExtension<KonektColors>? other, double t) => this;
}

/// Teinte (fond, icône) par catégorie de transaction/service.
({Color bg, Color fg}) kindTint(String kind) => switch (kind) {
  'send' || 'payout' || 'transfer' => (bg: KColors.primaryContainer, fg: KColors.primary),
  'plus' || 'topup' => (bg: KColors.successContainer, fg: KColors.success),
  'phone' || 'airtime' || 'data' => (bg: KColors.infoContainer, fg: KColors.tertiary),
  'bolt' || 'elec' => (bg: KColors.secondaryContainer, fg: const Color(0xFFB87A0E)),
  'cash' => (bg: KColors.warningContainer, fg: const Color(0xFFEA580C)),
  _ => (bg: const Color(0xFFF1F5F9), fg: const Color(0xFF334155)),
};
