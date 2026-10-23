import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ai_pdf/features/tools/services/offline_pdf_service.dart';

void main() {
  testWidgets('watermark text in any script is drawn, not left blank', (tester) async {
    for (final text in ['CONFIDENTIAL', 'نهێنی', 'محرمانه']) {
      final mark = await tester.runAsync(
        () => OfflinePdfService.instance.textImage(text, fontSize: 54, color: const ui.Color(0xFF000000)),
      );
      expect(mark!.width, greaterThan(10), reason: text);
      final decoded = img.decodePng(mark.image.bytes)!;
      final inked = decoded.where((p) => p.a > 0).length;
      expect(inked, greaterThan(0), reason: '$text has visible pixels');
    }
  });
}
