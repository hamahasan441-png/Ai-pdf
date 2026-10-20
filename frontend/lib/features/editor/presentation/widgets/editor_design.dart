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

  /// Floating contextual bars over the page.
  final Color barSurface;
  final Color barForeground;

  /// Soft hues for the detected-field overlay (design mode only).
  final Color detectIndigo;
  final Color detectTeal;
  final Color detectViolet;

  static EditorPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? darkPalette : lightPalette;
  }

  /// Dark editor chrome: deep navy-graphite, calm and premium.
  static final EditorPalette darkPalette = EditorPalette._(
    brightness: Brightness.dark,
    canvasBackground: const Color(0xFF10131C),
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

  /// Light editor chrome: cool paper tones that keep the page the focus.
  static final EditorPalette lightPalette = EditorPalette._(
    brightness: Brightness.light,
    canvasBackground: const Color(0xFFE4E7EF),
    fieldSurface: Colors.white,
    fieldHairline: Colors.black.withValues(alpha: 0.10),
    readOnlySurface: const Color(0xFFF1F2F5),
    focusTint: AppColors.primary.withValues(alpha: 0.08),
    selectionTint: AppColors.primary.withValues(alpha: 0.08),
    selectionBorder: AppColors.primary.withValues(alpha: 0.75),
    handleColor: AppColors.primaryDark,
    barSurface: const Color(0xF0182033),
    barForeground: Colors.white,
    detectIndigo: const Color(0xFF4C63D2),
    detectTeal: AppColors.accent,
    detectViolet: AppColors.toolViolet,
  );
}
