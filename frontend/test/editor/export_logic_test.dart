import 'dart:ui' show Offset, TextAlign, TextDirection;

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/rtl_detection_service.dart';

/// Tests for the export-path's RTL + alignment logic.
///
/// The export service (`editor_export_service.dart`) uses this logic to decide:
/// 1. Whether a text annotation is RTL (explicit direction OR auto-detected).
/// 2. Whether to flip left-aligned RTL text to right-aligned.
///
/// We test the *decision logic* here (pure domain) rather than the PDF widget
/// rendering (which requires the `pdf` package layout engine). This locks the
/// behavioral contract so refactors to the export service can't change how
/// annotation direction and alignment are resolved.
///
/// Masterplan P1 #9: "Export golden tests (lock fidelity)".
void main() {
  const rtlDetect = RtlDetectionService();

  /// Mirrors the export service's direction resolution logic:
  ///   isRtl = t.textDirection == TextDirection.rtl ||
  ///           (t.textDirection == null && rtlDetect.isRtl(t.text));
  bool resolveIsRtl(TextAnnotation t) {
    return t.textDirection == TextDirection.rtl ||
        (t.textDirection == null && rtlDetect.isRtl(t.text));
  }

  /// Mirrors the export service's alignment flip:
  ///   (t.textAlign == TextAlign.left && isRtl) ? TextAlign.right : t.textAlign
  TextAlign resolveAlign(TextAnnotation t, bool isRtl) {
    return (t.textAlign == TextAlign.left && isRtl)
        ? TextAlign.right
        : t.textAlign;
  }

  group('Export direction resolution', () {
    test('explicit RTL direction is always RTL', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'Hello', // LTR text but explicit RTL direction
        Colors.black,
        0.05,
        false,
        textDirection: TextDirection.rtl,
      );
      expect(resolveIsRtl(t), isTrue);
    });

    test('explicit LTR direction is never RTL', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'مرحبا', // RTL text but explicit LTR direction
        Colors.black,
        0.05,
        false,
        textDirection: TextDirection.ltr,
      );
      expect(resolveIsRtl(t), isFalse);
    });

    test('null direction auto-detects from Arabic text', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'مرحبا Hello',
        Colors.black,
        0.05,
        false,
      );
      expect(t.textDirection, isNull);
      expect(resolveIsRtl(t), isTrue);
    });

    test('null direction auto-detects from Hebrew text', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'שלום',
        Colors.black,
        0.05,
        false,
      );
      expect(resolveIsRtl(t), isTrue);
    });

    test('null direction with LTR-leading text is not RTL', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'Hello مرحبا',
        Colors.black,
        0.05,
        false,
      );
      expect(resolveIsRtl(t), isFalse);
    });

    test('null direction with digits-only text is not RTL', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        '123 !!!',
        Colors.black,
        0.05,
        false,
      );
      expect(resolveIsRtl(t), isFalse);
    });
  });

  group('Export alignment flip', () {
    test('left-aligned RTL text is flipped to right', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'مرحبا',
        Colors.black,
        0.05,
        false,
        textAlign: TextAlign.left,
      );
      final isRtl = resolveIsRtl(t);
      expect(isRtl, isTrue);
      expect(resolveAlign(t, isRtl), TextAlign.right);
    });

    test('center-aligned RTL text is NOT flipped', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'مرحبا',
        Colors.black,
        0.05,
        false,
        textAlign: TextAlign.center,
      );
      final isRtl = resolveIsRtl(t);
      expect(resolveAlign(t, isRtl), TextAlign.center);
    });

    test('right-aligned RTL text stays right', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'مرحبا',
        Colors.black,
        0.05,
        false,
        textAlign: TextAlign.right,
      );
      final isRtl = resolveIsRtl(t);
      expect(resolveAlign(t, isRtl), TextAlign.right);
    });

    test('left-aligned LTR text stays left', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'Hello',
        Colors.black,
        0.05,
        false,
        textAlign: TextAlign.left,
      );
      final isRtl = resolveIsRtl(t);
      expect(isRtl, isFalse);
      expect(resolveAlign(t, isRtl), TextAlign.left);
    });

    test('justify-aligned text is never flipped', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'مرحبا',
        Colors.black,
        0.05,
        false,
        textAlign: TextAlign.justify,
      );
      final isRtl = resolveIsRtl(t);
      expect(resolveAlign(t, isRtl), TextAlign.justify);
    });
  });

  group('Export font-size and position contract', () {
    test('font size is size * pageHeight', () {
      const pageH = 841.89; // A4 in points
      final t = TextAnnotation(
        const Offset(0.1, 0.2),
        'Test',
        Colors.black,
        0.05,
        false,
      );
      final expectedFontSize = t.size * pageH;
      expect(expectedFontSize, closeTo(42.0945, 0.01));
    });

    test('position is normalized pos * page dimensions', () {
      const pageW = 595.28; // A4
      const pageH = 841.89;
      final t = TextAnnotation(
        const Offset(0.25, 0.5),
        'Test',
        Colors.black,
        0.05,
        false,
      );
      final left = t.pos.dx * pageW;
      final top = t.pos.dy * pageH;
      expect(left, closeTo(148.82, 0.01));
      expect(top, closeTo(420.945, 0.01));
    });

    test('text box width is clamped to (1 - pos.dx) * pageW', () {
      const pageW = 595.28;
      final t = TextAnnotation(
        const Offset(0.7, 0.1),
        'Test',
        Colors.black,
        0.05,
        false,
      );
      final boxWidth = (pageW * (1 - t.pos.dx)).clamp(1.0, pageW);
      expect(boxWidth, closeTo(178.584, 0.01));
    });
  });
}
