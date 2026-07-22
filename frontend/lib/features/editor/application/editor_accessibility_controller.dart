import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Severity of an accessibility issue (Phase 37).
enum A11ySeverity { error, warning, info }

/// A single accessibility finding (Phase 37).
class A11yIssue {
  final String id;
  final String message;
  final String? fix;
  final A11ySeverity severity;
  final int? pageIndex;
  final String? annotationId;

  const A11yIssue({
    required this.id,
    required this.message,
    this.fix,
    required this.severity,
    this.pageIndex,
    this.annotationId,
  });
}

/// UI state for the accessibility checker (Phase 37).
class EditorAccessibilityState {
  final bool visible;
  final bool scanning;
  final List<A11yIssue> issues;
  final int errorCount;
  final int warningCount;
  final int infoCount;

  const EditorAccessibilityState({
    this.visible = false,
    this.scanning = false,
    this.issues = const [],
    this.errorCount = 0,
    this.warningCount = 0,
    this.infoCount = 0,
  });

  bool get hasIssues => issues.isNotEmpty;
  bool get isClean => issues.isEmpty && !scanning;
  int get totalCount => issues.length;

  EditorAccessibilityState copyWith({
    bool? visible,
    bool? scanning,
    List<A11yIssue>? issues,
    int? errorCount,
    int? warningCount,
    int? infoCount,
  }) =>
      EditorAccessibilityState(
        visible: visible ?? this.visible,
        scanning: scanning ?? this.scanning,
        issues: issues ?? this.issues,
        errorCount: errorCount ?? this.errorCount,
        warningCount: warningCount ?? this.warningCount,
        infoCount: infoCount ?? this.infoCount,
      );
}

/// Controller for the document accessibility checker (Phase 37).
///
/// Scans annotations on all pages for accessibility issues: low contrast text,
/// images without alt text, too-small font sizes, empty text boxes, unlabelled
/// form fields, etc. Presents a ranked issue list with suggested fixes. The
/// scan is synchronous (pure data analysis) so it's instant.
final editorAccessibilityProvider =
    StateNotifierProvider<EditorAccessibilityController, EditorAccessibilityState>(
        (ref) => EditorAccessibilityController());

class EditorAccessibilityController
    extends StateNotifier<EditorAccessibilityState> {
  EditorAccessibilityController() : super(const EditorAccessibilityState());

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  /// Run the accessibility audit.
  ///
  /// [annotations] is a map of page→list of annotation property maps.
  /// The check is pure-logic (no IO), so it runs synchronously.
  void scan(Map<int, List<Map<String, dynamic>>> annotations) {
    state = state.copyWith(scanning: true);
    final issues = <A11yIssue>[];
    int _id = 0;

    for (final entry in annotations.entries) {
      final page = entry.key;
      for (final ann in entry.value) {
        final type = ann['type'] as String? ?? '';
        final id = ann['id'] as String? ?? 'ann_${_id++}';

        // Check: empty text box
        if (type == 'text') {
          final text = ann['text'] as String? ?? '';
          if (text.trim().isEmpty) {
            issues.add(A11yIssue(
              id: 'empty_text_$id',
              message: 'Empty text box on page ${page + 1}',
              fix: 'Add text content or delete the annotation',
              severity: A11ySeverity.warning,
              pageIndex: page,
              annotationId: id,
            ));
          }
          // Check: small font size
          final size = ann['size'] as double? ?? 0.03;
          if (size < 0.018) {
            issues.add(A11yIssue(
              id: 'small_text_$id',
              message: 'Text may be too small to read on page ${page + 1}',
              fix: 'Increase font size to at least 12pt equivalent',
              severity: A11ySeverity.warning,
              pageIndex: page,
              annotationId: id,
            ));
          }
          // Check: low contrast
          final color = ann['color'] as int?;
          if (color != null) {
            final c = Color(color);
            // Very light text on assumed white background.
            final lum = (0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue) / 255;
            if (lum > 0.85) {
              issues.add(A11yIssue(
                id: 'low_contrast_$id',
                message: 'Low contrast text on page ${page + 1}',
                fix: 'Use a darker text color for better readability',
                severity: A11ySeverity.error,
                pageIndex: page,
                annotationId: id,
              ));
            }
          }
        }

        // Check: image without alt text
        if (type == 'image') {
          final alt = ann['alt'] as String? ?? '';
          if (alt.trim().isEmpty) {
            issues.add(A11yIssue(
              id: 'no_alt_$id',
              message: 'Image without alt text on page ${page + 1}',
              fix: 'Add descriptive alt text for screen readers',
              severity: A11ySeverity.error,
              pageIndex: page,
              annotationId: id,
            ));
          }
        }

        // Check: form field without label
        if (type == 'form') {
          final label = ann['label'] as String? ?? '';
          if (label.trim().isEmpty) {
            issues.add(A11yIssue(
              id: 'no_label_$id',
              message: 'Form field without label on page ${page + 1}',
              fix: 'Add a label so assistive technologies can identify it',
              severity: A11ySeverity.error,
              pageIndex: page,
              annotationId: id,
            ));
          }
        }
      }
    }

    // Sort: errors first, then warnings, then info.
    issues.sort((a, b) => a.severity.index.compareTo(b.severity.index));

    state = state.copyWith(
      scanning: false,
      issues: issues,
      errorCount: issues.where((i) => i.severity == A11ySeverity.error).length,
      warningCount: issues.where((i) => i.severity == A11ySeverity.warning).length,
      infoCount: issues.where((i) => i.severity == A11ySeverity.info).length,
    );
  }

  void clear() => state = const EditorAccessibilityState();
}
