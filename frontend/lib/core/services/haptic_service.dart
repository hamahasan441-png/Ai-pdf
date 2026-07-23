import 'package:flutter/services.dart';

/// Centralized haptic feedback service — provides consistent tactile feedback
/// across the app for different interaction types.
///
/// Uses the device's vibration motor to enhance UX:
/// - Light tap for selections and toggles
/// - Medium impact for confirmations and completions
/// - Heavy impact for destructive actions
/// - Selection click for scrolling/picking
class HapticService {
  const HapticService._();

  /// Light tap — for button presses, selections, toggles.
  static void lightTap() => HapticFeedback.lightImpact();

  /// Medium impact — for confirmations (save, export complete, form filled).
  static void medium() => HapticFeedback.mediumImpact();

  /// Heavy impact — for destructive actions (delete, clear, discard).
  static void heavy() => HapticFeedback.heavyImpact();

  /// Selection click — for scrollable pickers, page changes.
  static void selectionClick() => HapticFeedback.selectionClick();

  /// Vibrate — general-purpose notification vibration.
  static void vibrate() => HapticFeedback.vibrate();

  /// Success pattern — medium + delay + light (confirm completion).
  static Future<void> success() async {
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    HapticFeedback.lightImpact();
  }

  /// Error pattern — heavy + delay + heavy (alert user).
  static Future<void> error() async {
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    HapticFeedback.heavyImpact();
  }

  /// Page turn — selection click (for viewer page navigation).
  static void pageTurn() => HapticFeedback.selectionClick();

  /// Undo/redo — light tap.
  static void undoRedo() => HapticFeedback.lightImpact();

  /// Annotation placed — medium impact (confirm placement).
  static void annotationPlaced() => HapticFeedback.mediumImpact();

  /// Long press detected — selection click.
  static void longPress() => HapticFeedback.selectionClick();
}
