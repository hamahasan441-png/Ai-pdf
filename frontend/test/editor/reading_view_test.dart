import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/image_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_reading_view.dart';

// A 1×1 white PNG.
final png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
  0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
  0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  test('page offsets add page heights and gaps', () {
    double aspect(int i) => i.isEven ? 0.5 : 1.0; // tall, square
    expect(EditorReadingView.offsetOf(0, 100, aspect), EditorReadingView.gap / 2);
    expect(EditorReadingView.offsetOf(2, 100, aspect), EditorReadingView.gap / 2 + 200 + 12 + 100 + 12);
  });

  testWidgets('missing pages are requested, a tap opens the page', (tester) async {
    final requested = <int>{};
    int? opened;
    final layer = PageLayer()..items.add(TextAnnotation(const Offset(0.1, 0.1), 'Hello', Colors.black, 0.03, false));
    final images = ImageAnnotationRenderer();
    addTearDown(images.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        EditorReadingView(
          pageCount: 30,
          initialPage: 5,
          aspectOf: (_) => 0.75,
          bytesOf: (i) => i == 5 ? png : null,
          requestPage: requested.add,
          layerOf: (i) => i == 5 ? layer : null,
          formLayerOf: (_) => null,
          imageRenderer: images,
          stampRenderer: const StampAnnotationRenderer(),
          onOpenPage: (i) => opened = i,
        ),
      ]),
    ));
    await tester.pump();
    expect(requested, isNotEmpty);
    expect(requested, isNot(contains(5)), reason: 'page 5 already has a bitmap');
    expect(requested.every((i) => (i - 5).abs() <= 3), isTrue, reason: 'only pages near the view: $requested');
    expect(find.bySemanticsLabel('6 / 30'), findsOneWidget, reason: 'opens at the current page');
    // The page is taller than the view; tap its visible top part.
    await tester.tapAt(tester.getTopLeft(find.bySemanticsLabel('6 / 30')) + const Offset(40, 40));
    expect(opened, 5);
  });
}
