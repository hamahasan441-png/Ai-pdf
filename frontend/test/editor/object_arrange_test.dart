import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/image_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/object_arrange.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_canvas_painter.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_object_finish_dialog.dart';

void main() {
  ShapeAnnotation box([Offset start = const Offset(0.1, 0.2), Offset end = const Offset(0.3, 0.4)]) =>
      ShapeAnnotation(ShapeType.rect, start, end, const Color(0xFF000000), 0.004);

  test('nudge steps a mark and refuses a locked one', () {
    final shape = box();
    expect(nudgeAnnotation(shape, const Offset(fineNudge, 0)), isTrue);
    expect(shape.start.dx, closeTo(0.1 + fineNudge, 0.0001));
    shape.locked = true;
    expect(nudgeAnnotation(shape, const Offset(coarseNudge, 0)), isFalse);
    expect(shape.start.dx, closeTo(0.1 + fineNudge, 0.0001));
    expect(nudgeAnnotation(box(), Offset.zero), isFalse);
  });

  test('one object centres on the page', () {
    final shape = box();
    expect(centerAnnotationOnPage(shape), isTrue);
    expect(shape.bounds.center.dx, closeTo(0.5, 0.001));
    expect(shape.bounds.center.dy, closeTo(0.5, 0.001));

    final locked = box()..locked = true;
    final before = locked.bounds.center;
    expect(centerAnnotationOnPage(locked), isFalse);
    expect(locked.bounds.center, before);
  });

  test('a mark meets any edge of the page, and stays if it is already there', () {
    final shape = box();
    expect(alignAnnotationToPage(shape, PageEdge.left), isTrue);
    expect(shape.bounds.left, closeTo(0, 0.001));
    expect(alignAnnotationToPage(shape, PageEdge.left), isFalse);

    expect(alignAnnotationToPage(shape, PageEdge.right), isTrue);
    expect(shape.bounds.right, closeTo(1, 0.001));
    expect(alignAnnotationToPage(shape, PageEdge.top), isTrue);
    expect(shape.bounds.top, closeTo(0, 0.001));
    expect(alignAnnotationToPage(shape, PageEdge.bottom), isTrue);
    expect(shape.bounds.bottom, closeTo(1, 0.001));

    final mid = box();
    expect(alignAnnotationToPage(mid, PageEdge.hCenter), isTrue);
    expect(mid.bounds.center.dx, closeTo(0.5, 0.001));
    expect(mid.bounds.top, closeTo(0.2, 0.001));
    expect(alignAnnotationToPage(mid, PageEdge.vCenter), isTrue);
    expect(mid.bounds.center.dy, closeTo(0.5, 0.001));

    final locked = box()..locked = true;
    expect(alignAnnotationToPage(locked, PageEdge.right), isFalse);
    expect(locked.bounds.left, closeTo(0.1, 0.001));
  });

  test('opacity fades ink and a stamp, not a locked mark or a form field', () {
    final shape = box();
    expect(setAnnotationOpacity(shape, 0.4), isTrue);
    expect(shape.opacity, closeTo(0.4, 0.001));
    expect(setAnnotationOpacity(shape, 0.4), isFalse);
    expect(setAnnotationOpacity(shape, 2), isTrue);
    expect(shape.opacity, 1);
    expect(setAnnotationOpacity(shape, 0.01), isTrue);
    expect(shape.opacity, closeTo(0.1, 0.001));

    final locked = box()..locked = true;
    expect(setAnnotationOpacity(locked, 0.5), isFalse);
    expect(locked.opacity, 1);

    final field = FormFieldAnnotation(
      pos: Offset.zero,
      width: 0.2,
      height: 0.05,
      fieldKind: FormFieldKind.text,
      label: 'Name',
    );
    expect(supportsOpacity(field), isFalse);
    expect(setAnnotationOpacity(field, 0.5), isFalse);
    expect(field.opacity, 1);
  });

  test('same width and height copy the front-most mark and keep the place', () {
    final back = box(const Offset(0.1, 0.1), const Offset(0.4, 0.3));
    final front = box(const Offset(0.5, 0.2), const Offset(0.7, 0.6));
    expect(matchAnnotationSize([back, front], width: true, height: false), 1);
    expect(back.bounds.left, closeTo(0.1, 0.001));
    expect(back.bounds.width, closeTo(0.2, 0.001));
    expect(back.bounds.height, closeTo(0.2, 0.001));
    expect(front.bounds.width, closeTo(0.2, 0.001));

    final tall = box(const Offset(0.1, 0.1), const Offset(0.3, 0.2));
    final short = box(const Offset(0.4, 0.4), const Offset(0.6, 0.8));
    expect(matchAnnotationSize([tall, short], width: false, height: true), 1);
    expect(tall.bounds.height, closeTo(0.4, 0.001));
    expect(tall.bounds.top, closeTo(0.1, 0.001));
    expect(matchAnnotationSize([back], width: true, height: true), 0);

    final text = TextAnnotation(const Offset(0.05, 0.05), 'Hello', const Color(0xFF000000), 0.02, false);
    final frame = box(const Offset(0.2, 0.2), const Offset(0.5, 0.4));
    expect(matchAnnotationSize([text, frame], width: true, height: false), 1);
    expect(text.width, closeTo(0.3, 0.001));
  });

  test('moving or fading a mark repaints, an unchanged page does not', () {
    final shape = box(const Offset(0.1, 0.1), const Offset(0.4, 0.3));
    final images = ImageAnnotationRenderer();
    const stamps = StampAnnotationRenderer();
    EditorCanvasPainter paint() => EditorCanvasPainter(
          const [],
          [shape],
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

    final before = paint();
    expect(paint().shouldRepaint(before), isFalse);
    shape.end = const Offset(0.8, 0.7);
    expect(paint().shouldRepaint(before), isTrue);
    final faded = paint();
    shape.opacity = 0.4;
    expect(paint().shouldRepaint(faded), isTrue);
  });

  testWidgets('the align and opacity dialogs report what was chosen', (tester) async {
    PageEdge? edge;
    double? opacity;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () async => edge = await showEditorPageAlignDialog(context),
                child: const Text('align'),
              ),
              TextButton(
                onPressed: () async => opacity = await showEditorOpacityDialog(context, opacity: 0.4),
                child: const Text('fade'),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.tap(find.text('align'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Align left'));
    await tester.pumpAndSettle();
    expect(edge, PageEdge.left);

    await tester.tap(find.text('fade'));
    await tester.pumpAndSettle();
    expect(find.text('40%'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(opacity, closeTo(0.4, 0.001));
  });
}
