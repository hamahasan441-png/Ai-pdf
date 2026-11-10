import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/core/config/kurdish_localizations.dart';
import 'package:ai_pdf/features/editor/data/image_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/workspace_commands.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_canvas_painter.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_geometry_dialog.dart';

void main() {
  const pageW = 595.28;
  const pageH = 841.89;

  test('a typed millimetre box places a shape, and a comma is a decimal', () {
    expect(parseMillimetres('12,5'), 12.5);
    expect(parseMillimetres(' 8 '), 8);
    expect(parseMillimetres(''), isNull);
    expect(parseMillimetres('nein'), isNull);
    expect(formatMillimetres(10), '10.0');

    final shape = ShapeAnnotation(
      ShapeType.rect,
      const Offset(0.1, 0.1),
      const Offset(0.3, 0.2),
      Colors.black,
      1,
    );
    expect(
      placeByMillimetres(
        shape,
        const MillimetreBox(left: 10, top: 15, width: 40, height: 25),
        pageWidthPt: pageW,
        pageHeightPt: pageH,
      ),
      isTrue,
    );
    final got = millimetreBoxOf(shape.bounds, pageWidthPt: pageW, pageHeightPt: pageH)!;
    expect(got.left, closeTo(10, 0.05));
    expect(got.top, closeTo(15, 0.05));
    expect(got.width, closeTo(40, 0.05));
    expect(got.height, closeTo(25, 0.05));
  });

  test('a line keeps its length when a side is left at zero, and a lock does not move', () {
    final line = ShapeAnnotation(
      ShapeType.line,
      const Offset(0.2, 0.3),
      const Offset(0.5, 0.3),
      Colors.black,
      1,
    );
    final before = millimetreBoxOf(line.bounds, pageWidthPt: pageW, pageHeightPt: pageH)!;
    expect(
      placeByMillimetres(
        line,
        const MillimetreBox(left: 20, top: 40, width: 0, height: 0),
        pageWidthPt: pageW,
        pageHeightPt: pageH,
      ),
      isTrue,
    );
    final got = millimetreBoxOf(line.bounds, pageWidthPt: pageW, pageHeightPt: pageH)!;
    expect(got.left, closeTo(20, 0.2));
    expect(got.top, closeTo(40, 0.2));
    expect(got.width, closeTo(before.width, 0.2));
    expect(got.height, lessThan(0.3));

    final image = ImageAnnotation(pos: const Offset(0.1, 0.1), width: 0.2, height: 0.2, bytes: Uint8List(0));
    image.locked = true;
    expect(
      placeByMillimetres(
        image,
        const MillimetreBox(left: 30, top: 30, width: 20, height: 20),
        pageWidthPt: pageW,
        pageHeightPt: pageH,
      ),
      isFalse,
    );
    expect(image.pos, const Offset(0.1, 0.1));
    final loose = ShapeAnnotation(ShapeType.rect, Offset.zero, const Offset(0.2, 0.2), Colors.black, 1);
    expect(
      placeByMillimetres(loose, const MillimetreBox(left: 1, top: 1, width: 10, height: 10), pageWidthPt: 0, pageHeightPt: pageH),
      isFalse,
    );
    expect(loose.end, const Offset(0.2, 0.2));
  });

  test('Tab walks the visible marks and wraps, skipping a hidden one', () {
    final a = ShapeAnnotation(ShapeType.rect, Offset.zero, const Offset(0.1, 0.1), Colors.black, 1);
    final b = ShapeAnnotation(ShapeType.oval, const Offset(0.2, 0.2), const Offset(0.3, 0.3), Colors.black, 1);
    final hidden = ShapeAnnotation(ShapeType.rect, const Offset(0.4, 0.4), const Offset(0.5, 0.5), Colors.black, 1)
      ..visible = false;
    final page = [a, b, hidden];
    expect(selectableMarks(page), [a, b]);
    expect(cycleMark(page, null, backward: false), same(a));
    expect(cycleMark(page, a, backward: false), same(b));
    expect(cycleMark(page, b, backward: false), same(a));
    expect(cycleMark(page, a, backward: true), same(b));
    expect(cycleMark(page, hidden, backward: false), same(a));
    expect(cycleMark(const <EditorAnnotation>[], null, backward: true), isNull);
  });

  test('moving or recolouring a mark repaints, an unchanged page does not', () {
    final shape = ShapeAnnotation(ShapeType.rect, const Offset(0.1, 0.1), const Offset(0.4, 0.3), Colors.black, 2);
    final images = ImageAnnotationRenderer();
    const stamps = StampAnnotationRenderer();
    EditorCanvasPainter paint(List<ShapeAnnotation> shapes) => EditorCanvasPainter(
          const [],
          shapes,
          const [],
          const [],
          images,
          stamps,
          const [],
          null,
          null,
          null,
          Colors.black,
          2,
          false,
        );

    final before = paint([shape]);
    expect(paint([shape]).shouldRepaint(before), isFalse);

    shape.end = const Offset(0.8, 0.7);
    expect(paint([shape]).shouldRepaint(before), isTrue);

    final coloured = paint([shape]);
    shape.color = Colors.red;
    expect(paint([shape]).shouldRepaint(coloured), isTrue);

    final other = ShapeAnnotation(ShapeType.oval, Offset.zero, const Offset(0.2, 0.2), Colors.blue, 1);
    expect(paint([other, shape]).shouldRepaint(paint([shape, other])), isTrue);
  });

  testWidgets('the place dialog returns the typed millimetres', (tester) async {
    MillimetreBox? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [...AppLocalizations.localizationsDelegates, ...kurdishFallbackDelegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showEditorGeometryDialog(
                context,
                initial: const MillimetreBox(left: 1, top: 2, width: 3, height: 4),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Place by millimetres'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '11,5');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result?.left, 11.5);
    expect(result?.top, 2);
    expect(result?.width, 3);
    expect(result?.height, 4);
  });
}
