import 'package:flutter/material.dart';

import 'package:ai_pdf/core/theme/app_theme.dart';

/// Design tokens for the PDF editor workspace.
///
/// The editor floats over the user's document, so its chrome must be quiet:
/// deep graphite-navy surfaces in the dark theme, cool paper tones in the
/// light theme, and a single restrained indigo accent for selection.
///
/// These tokens exist so the editor never again hard-codes loud blues for
/// selection chrome. Selection is communicated with *tints*; borders and
/// handles appear only in the explicit Move/Resize (transform) mode.
class EditorPalette {
  EditorPalette._({
    required this.brightness,
    required this.canvasBackground,
    required this.fieldSurface,
    required this.fieldHairline,
    required this.readOnlySurface,
    required this.focusTint,
    required this.selectionTint,
    required this.selectionBorder,
    required this.handleColor,
    required this.barSurface,
    required this.barForeground,
    required this.detectIndigo,
    required this.detectTeal,
    required this.detectViolet,
  });

  final Brightness brightness;

  /// The surface behind the PDF page.
  final Color canvasBackground;

  /// Opaque surface for a form field value (covers the file's stale
  /// appearance without painting a coloured "selection" box).
  final Color fieldSurface;

  /// Nearly invisible frame that mimics a printed form field box.
  final Color fieldHairline;

  /// Surface of a field the document marks read-only.
  final Color readOnlySurface;

  /// The *only* cue a focused (tap-to-fill) field gets: a light accent wash.
  final Color focusTint;

  /// Selection cue for canvas objects: a light accent wash, no border.
  final Color selectionTint;

  /// Hairline used for the transform-mode bounding box (Move/Resize only).
  final Color selectionBorder;

  /// Move/Resize handles; only visible in transform mode.
  final Color handleColor;

  /// Floating contextual bars over the page (and the editor's own bars).
  final Color barSurface;
  final Color barForeground;

  /// Soft hues for the detected-field overlay (design mode only).
  final Color detectIndigo;
  final Color detectTeal;
  final Color detectViolet;

  /// Bar ink for secondary content: inactive tools and labels.
  Color get barMuted => barForeground.withValues(alpha: brightness == Brightness.dark ? 0.62 : 0.66);

  /// Hairlines between the bars and the page.
  Color get hairline => brightness == Brightness.dark ? const Color(0x1FFFFFFF) : const Color(0xFFE6E8EB);

  /// The quiet pill behind the active tool or mode: a wash of the accent,
  /// never a second colour, so the active thing is obvious without shouting.
  Color get activePill => accent.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.12);

  /// The one accent: the active tool's icon and the primary action.
  Color get accent => brightness == Brightness.dark ? AppColors.primaryLight : AppColors.primary;

  /// Text on the accent: white on the deep light-theme blue, near-black on
  /// the paler dark-theme one (white there is under 3:1).
  Color get onAccent => brightness == Brightness.dark ? const Color(0xFF111827) : Colors.white;

  static EditorPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? darkPalette : lightPalette;
  }

  /// Dark editor chrome: deep navy-graphite, calm and premium.
  static final EditorPalette darkPalette = EditorPalette._(
    brightness: Brightness.dark,
    canvasBackground: const Color(0xFF12151C),
    fieldSurface: Colors.white,
    fieldHairline: Colors.black.withValues(alpha: 0.10),
    readOnlySurface: const Color(0xFFF1F2F5),
    focusTint: AppColors.primary.withValues(alpha: 0.10),
    selectionTint: AppColors.primaryLight.withValues(alpha: 0.14),
    selectionBorder: AppColors.primaryLight.withValues(alpha: 0.85),
    handleColor: AppColors.primaryLight,
    barSurface: const Color(0xF01B2130),
    barForeground: Colors.white,
    detectIndigo: const Color(0xFF4C63D2),
    detectTeal: AppColors.accent,
    detectViolet: AppColors.toolViolet,
  );

  /// Light editor chrome: a quiet neutral around the page and white bars
  /// with dark ink, so the document is the only thing that draws the eye.
  static final EditorPalette lightPalette = EditorPalette._(
    brightness: Brightness.light,
    canvasBackground: const Color(0xFFF3F1EC),
    fieldSurface: Colors.white,
    fieldHairline: Colors.black.withValues(alpha: 0.10),
    readOnlySurface: const Color(0xFFF1F2F5),
    focusTint: AppColors.primary.withValues(alpha: 0.08),
    selectionTint: AppColors.primary.withValues(alpha: 0.08),
    selectionBorder: AppColors.primary.withValues(alpha: 0.75),
    handleColor: AppColors.primaryDark,
    barSurface: Colors.white,
    barForeground: const Color(0xFF1F2328),
    detectIndigo: const Color(0xFF4C63D2),
    detectTeal: AppColors.accent,
    detectViolet: AppColors.toolViolet,
  );
}

/// Shared geometry for the editor chrome so every bar, sheet, handle and
/// panel feels like the same quiet instrument: generous targets, soft
/// corners, and one floating shadow.
class EditorChrome {
  EditorChrome._();

  /// Comfortable finger target. Visuals can be smaller; the hit area is not.
  static const double touch = 48;

  static const double radius = 14;
  static const double radiusSheet = 24;

  static List<BoxShadow> floatShadow(Brightness brightness) => [
        BoxShadow(
          color: const Color(0xFF1B2130).withValues(alpha: brightness == Brightness.dark ? 0.5 : 0.12),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ];

  static BoxDecoration floating({
    required Color color,
    required Color border,
    required Brightness brightness,
  }) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radiusSheet),
        border: Border.all(color: border),
        boxShadow: floatShadow(brightness),
      );

  static ShapeBorder get menuShape => RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
}
