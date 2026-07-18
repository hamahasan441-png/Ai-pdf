import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pdoczy palette — calm, professional, trustworthy.
///
/// Color psychology: a serene indigo-blue primary conveys trust, focus and
/// stability; a soft teal accent adds clarity and freshness without alarm; the
/// semantic colors are intentionally muted (no harsh reds/oranges) and the
/// neutrals are layered and low-contrast so the interface feels quiet and
/// unhurried. The goal is an app that feels effortless to return to.
///
/// The public API (field + gradient names) is unchanged so existing screens
/// keep compiling — only the values are tuned for calm.
class AppColors {
  AppColors._();

  // Primary — serene indigo-blue (trust · focus · calm)
  static const Color primaryDark = Color(0xFF2B3A8F);
  static const Color primary = Color(0xFF4C63D2);
  static const Color primaryLight = Color(0xFF8A97E8);

  // Accent — soft teal (clarity · freshness), replaces the old loud coral
  static const Color accent = Color(0xFF2BB5A6);
  static const Color accentLight = Color(0xFF63CFC2);

  // Semantic — muted so nothing feels aggressive
  static const Color success = Color(0xFF2E9E7B);
  static const Color warning = Color(0xFFCF9A4E);
  static const Color error = Color(0xFFD9636B);

  // Neutrals — soft, layered, low glare
  static const Color bgLight = Color(0xFFF4F6FA);
  static const Color bgDark = Color(0xFF0E121B);
  static const Color surfaceDark = Color(0xFF171C28);
  static const Color cardDark = Color(0xFF212838);

  // Gentle gradients — subtle tonal shifts, never high-contrast jumps
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4C63D2), Color(0xFF6373DE)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF2B3A8F), Color(0xFF4056C4), Color(0xFF4C63D2)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF2BB5A6), Color(0xFF63CFC2)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );

  // Calm, categorized hues for tool icons (no rainbow).
  static const Color toolIndigo = Color(0xFF4C63D2); // core PDF ops
  static const Color toolTeal = Color(0xFF2BB5A6);   // scan / read / transform
  static const Color toolBlue = Color(0xFF4F86C6);   // view / convert
  static const Color toolGreen = Color(0xFF2E9E7B);  // create / secure
  static const Color toolViolet = Color(0xFF7E7BD4); // AI / smart
  static const Color toolAmber = Color(0xFFC99A52);  // organize
  static const Color toolSlate = Color(0xFF6A7FBF);  // edit / pages
}

class AppTheme {
  AppTheme._();

  // Softer, more generous geometry reads as calmer and more premium.
  static const double _rCard = 20;
  static const double _rField = 16;
  static const double _rButton = 16;
  static const double _rSheet = 28;

  static final lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bgLight,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE6E9FB),
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD9F2EE),
      onSecondaryContainer: Color(0xFF06342E),
      tertiary: Color(0xFF7E7BD4),
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF1B2130),
      onSurfaceVariant: Color(0xFF6B7488),
      outline: Color(0xFFD8DEE9),
      outlineVariant: Color(0xFFE8ECF3),
      error: AppColors.error,
      onError: Colors.white,
      surfaceContainerHighest: Color(0xFFEEF1F7),
    ),
    textTheme: _calmTextTheme(const Color(0xFF1B2130), const Color(0xFF6B7488)),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: AppColors.bgLight,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(color: Color(0xFF1B2130), fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      iconTheme: IconThemeData(color: Color(0xFF3C455A)),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_rCard),
        side: const BorderSide(color: Color(0xFFE8ECF3), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFEEF1F7),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(_rField), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_rField), borderSide: const BorderSide(color: Color(0xFFE8ECF3))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_rField), borderSide: const BorderSide(color: AppColors.primary, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_rField), borderSide: const BorderSide(color: AppColors.error)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: const TextStyle(color: Color(0xFF6B7488)),
      hintStyle: const TextStyle(color: Color(0xFF9AA3B8)),
      prefixIconColor: const Color(0xFF9AA3B8),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rButton)),
      textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    )),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rButton)),
      textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rButton)),
      side: const BorderSide(color: Color(0xFFD8DEE9)),
      textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
    )),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: StadiumBorder(),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFEEF1F7),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1B2130),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE8ECF3), thickness: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(_rSheet))),
    ),
    splashFactory: InkSparkle.splashFactory,
  );

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bgDark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF8A97E8),
      onPrimary: Color(0xFF141A2E),
      primaryContainer: Color(0xFF313C8C),
      onPrimaryContainer: Color(0xFFE6E9FB),
      secondary: Color(0xFF63CFC2),
      onSecondary: Color(0xFF06342E),
      secondaryContainer: Color(0xFF124F47),
      onSecondaryContainer: Color(0xFFD9F2EE),
      tertiary: Color(0xFF9E9BE6),
      onTertiary: Color(0xFF161634),
      surface: AppColors.surfaceDark,
      onSurface: Color(0xFFE6E9F0),
      onSurfaceVariant: Color(0xFF9AA3B8),
      outline: Color(0xFF39415A),
      outlineVariant: Color(0xFF262C3B),
      error: Color(0xFFE59AA0),
      onError: Color(0xFF3A0E12),
      surfaceContainerHighest: AppColors.cardDark,
    ),
    textTheme: _calmTextTheme(const Color(0xFFE6E9F0), const Color(0xFF9AA3B8)),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: AppColors.bgDark,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(color: Color(0xFFE6E9F0), fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      iconTheme: IconThemeData(color: Color(0xFFB6BECF)),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_rCard),
        side: const BorderSide(color: Color(0xFF262C3B), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardDark,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(_rField), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_rField), borderSide: const BorderSide(color: Color(0xFF39415A))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_rField), borderSide: const BorderSide(color: Color(0xFF8A97E8), width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: const TextStyle(color: Color(0xFF9AA3B8)),
      hintStyle: const TextStyle(color: Color(0xFF6B7488)),
      prefixIconColor: const Color(0xFF6B7488),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rButton)),
      textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    )),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rButton)),
      textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rButton)),
      side: const BorderSide(color: Color(0xFF39415A)),
      textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: const Color(0xFF8A97E8),
      textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
    )),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF8A97E8),
      foregroundColor: Color(0xFF141A2E),
      elevation: 2,
      shape: StadiumBorder(),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.cardDark,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF262C3B),
      contentTextStyle: const TextStyle(color: Color(0xFFE6E9F0), fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF262C3B), thickness: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(_rSheet))),
    ),
    splashFactory: InkSparkle.splashFactory,
  );

  /// Calm typography: comfortable line-height and gentle letter-spacing so text
  /// feels relaxed and easy to read. Sizes stay close to Material defaults to
  /// avoid disturbing existing layouts.
  static TextTheme _calmTextTheme(Color primary, Color secondary) {
    return TextTheme(
      headlineSmall: TextStyle(color: primary, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.25),
      titleLarge: TextStyle(color: primary, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.3),
      titleMedium: TextStyle(color: primary, fontWeight: FontWeight.w600, letterSpacing: -0.1, height: 1.3),
      titleSmall: TextStyle(color: primary, fontWeight: FontWeight.w600, height: 1.3),
      bodyLarge: TextStyle(color: primary, height: 1.45),
      bodyMedium: TextStyle(color: secondary, height: 1.45),
      bodySmall: TextStyle(color: secondary, height: 1.4),
      labelLarge: TextStyle(color: primary, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    );
  }
}
