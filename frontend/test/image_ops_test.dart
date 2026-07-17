import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_pdf/core/image/image_ops.dart';

void main() {
  // Bytes that are NOT a valid image, so decodeImage returns null. This lets us
  // verify the fallback/skip behavior without shipping binary fixtures.
  final garbage = Uint8List.fromList(const [0, 1, 2, 3, 4, 5, 6, 7]);

  group('applyImageOp fallback behavior on undecodable input', () {
    test('jpegReencode returns the original bytes when it cannot decode', () {
      final out = applyImageOp(ImageOp(
        type: ImageOpType.jpegReencode,
        bytes: garbage,
        quality: 55,
      ));
      expect(out, equals(garbage));
      expect(isUndecodable(out), isFalse);
    });

    test('jpegRotate returns the undecodable sentinel (empty) so caller skips', () {
      final out = applyImageOp(ImageOp(
        type: ImageOpType.jpegRotate,
        bytes: garbage,
        degrees: 90,
      ));
      expect(out, isEmpty);
      expect(isUndecodable(out), isTrue);
    });

    test('jpegDownscaleLongEdge returns original bytes when maxEdge is null', () {
      final out = applyImageOp(ImageOp(
        type: ImageOpType.jpegDownscaleLongEdge,
        bytes: garbage,
      ));
      expect(out, equals(garbage));
    });

    test('pngDownscaleLongEdge returns original bytes when it cannot decode', () {
      final out = applyImageOp(ImageOp(
        type: ImageOpType.pngDownscaleLongEdge,
        bytes: garbage,
        maxEdge: 1200,
      ));
      expect(out, equals(garbage));
    });

    test('jpegCompress throws when it cannot decode (surfaced to the user)', () {
      expect(
        () => applyImageOp(ImageOp(
          type: ImageOpType.jpegCompress,
          bytes: garbage,
          quality: 70,
        )),
        throwsA(isA<Exception>()),
      );
    });
  });
}
