import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static const radiusField = 18.0;
  static const radiusCard = 16.0;
  static const radiusDialog = 28.0;

  static const colorScheme = ColorScheme.light(
    primary: KColors.primary,
    onPrimary: KColors.onPrimary,
    primaryContainer: KColors.primaryContainer,
    onPrimaryContainer: KColors.primary,
    secondary: KColors.secondary,
    onSecondary: KColors.primary,
    secondaryContainer: KColors.secondaryContainer,
    onSecondaryContainer: KColors.onSecondaryContainer,
    tertiary: KColors.tertiary,
    onTertiary: KColors.onPrimary,
    error: KColors.error,
    onError: KColors.onPrimary,
    errorContainer: KColors.errorContainer,
    onErrorContainer: KColors.onErrorContainer,
    surface: KColors.surface,
    onSurface: KColors.primary,
    onSurfaceVariant: KColors.onSurfaceVariant,
    surfaceContainer: KColors.surfaceContainer,
    surfaceContainerLow: KColors.background,
    surfaceContainerHighest: KColors.surfaceContainer,
    outline: KColors.outline,
    outlineVariant: KColors.outlineVariant,
  );

  static ThemeData light({bool useGoogleFonts = true}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: useGoogleFonts ? GoogleFonts.plusJakartaSans().fontFamily : null,
    );
    final textTheme = base.textTheme.apply(bodyColor: KColors.primary, displayColor: KColors.primary);
    const stadium = StadiumBorder();
    const btnSize = Size.fromHeight(56);
    final btnText = textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: KColors.background,
      extensions: const [KonektColors()],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: KColors.primary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: btnSize,
          shape: stadium,
          textStyle: btnText,
          disabledBackgroundColor: KColors.primary.withValues(alpha: 0.4),
          disabledForegroundColor: KColors.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: btnSize,
          shape: stadium,
          textStyle: btnText,
          side: const BorderSide(color: KColors.outlineVariant, width: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: KColors.tertiary,
          shape: stadium,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KColors.fieldFill,
        hintStyle: const TextStyle(color: KColors.outline),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: KColors.outlineVariant, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: KColors.outlineVariant, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: KColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: KColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: KColors.error, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: KColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: KColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusDialog)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: KColors.surfaceContainer,
        indicatorColor: KColors.navIndicator,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => textTheme.labelMedium?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: s.contains(WidgetState.selected) ? KColors.primary : KColors.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? KColors.primary : KColors.onSurfaceVariant),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: KColors.secondaryContainer,
          selectedForegroundColor: KColors.primary,
          foregroundColor: KColors.primary,
          side: const BorderSide(color: KColors.outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: KColors.primary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: KColors.onPrimary, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: KColors.divider, thickness: 1, space: 1),
      listTileTheme: const ListTileThemeData(iconColor: KColors.primary, textColor: KColors.primary),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: KColors.primary),
      chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder(), side: BorderSide.none),
    );
  }
}
