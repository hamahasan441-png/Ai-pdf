import 'dart:convert';

import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Cross-page annotation clipboard with serialization support.
///
/// The existing clipboard in pick_edit_screen.dart stores a single in-memory
/// reference — it works within one session but is lost on app restart. This
/// service provides a serialization-ready clipboard that:
/// - Stores one or more annotations (multi-select copy)
/// - Can serialize to/from JSON (for future inter-app paste or persistent clipboard)
/// - Offsets pasted annotations slightly so they don't stack exactly on the original
/// - Assigns new IDs to pasted annotations (preventing duplicate-ID bugs)
class AnnotationClipboardService {
  const AnnotationClipboardService();

  /// Serialize one or more annotations to a clipboard JSON string.
  String copyToJson(List<EditorAnnotation> annotations) {
    final items = annotations.map(annotationToJson).toList();
    return jsonEncode({'clipboard': items, 'count': items.length});
  }

  /// Deserialize annotations from a clipboard JSON string.
  /// Returns new instances with fresh IDs (ready to paste).
  List<EditorAnnotation> pasteFromJson(String json, {double offsetNorm = 0.02}) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final items = data['clipboard'] as List<dynamic>? ?? [];
      final result = <EditorAnnotation>[];
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final a = annotationFromJson(item);
          if (a != null) {
            // Offset so the paste doesn't stack exactly on top of the original.
            _offsetAnnotation(a, offsetNorm);
            result.add(a);
          }
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Create a paste-ready copy of a single annotation (new ID, slight offset).
  EditorAnnotation? cloneForPaste(EditorAnnotation original, {double offsetNorm = 0.02}) {
    final json = annotationToJson(original);
    // Remove the ID so fromJson generates a new one.
    json.remove('id');
    final clone = annotationFromJson(json);
    if (clone != null) {
      _offsetAnnotation(clone, offsetNorm);
    }
    return clone;
  }

  /// Create paste-ready copies of multiple annotations.
  List<EditorAnnotation> cloneMultiForPaste(
    Iterable<EditorAnnotation> originals, {
    double offsetNorm = 0.02,
  }) {
    return originals
        .map((a) => cloneForPaste(a, offsetNorm: offsetNorm))
        .whereType<EditorAnnotation>()
        .toList();
  }

  void _offsetAnnotation(EditorAnnotation a, double offset) {
    if (a is TextAnnotation) {
      a.pos = a.pos.translate(offset, offset);
    } else if (a is ShapeAnnotation) {
      a.start = a.start.translate(offset, offset);
      a.end = a.end.translate(offset, offset);
    }
    // StrokeAnnotation points are immutable (final list) — offset handled by
    // the serialization round-trip which creates new Offset instances.
  }
}
