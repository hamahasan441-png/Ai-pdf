import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/core/config/kurdish_localizations.dart';

import 'package:ai_pdf/features/editor/data/editor_status.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_status_bar.dart';

void main() {
  test('a fitted page is 100 percent and zoom stays in range', () {
    expect(zoomPercent(1), 100);
    expect(zoomPercent(1.42), 142);
    expect(zoomPercent(0), 100);
    expect(nextZoom(1, zoomIn: true), closeTo(1.25, 0.001));
    expect(nextZoom(1, zoomIn: false), closeTo(0.8, 0.001));
    expect(nextZoom(5, zoomIn: true), 5);
    expect(nextZoom(0.5, zoomIn: false), 0.5);
  });

  test('standard pages are named and a selection is sized in millimetres', () {
    final a4 = paperSize(595.28, 841.89);
    expect(a4.name, 'A4');
    expect(a4.millimetres, '210 × 297 mm');
    expect(paperSize(841.89, 595.28).name, 'A4');
    expect(paperSize(612, 792).name, 'Letter');
    expect(paperSize(400, 300).name, isNull);
    expect(paperSize(400, 300).millimetres, '141 × 106 mm');

    final box = selectionMillimetres(
      const Rect.fromLTWH(0, 0, 0.5, 0.25),
      pageWidthPt: 720,
      pageHeightPt: 720,
    );
    expect(box, '127.0 × 63.5 mm');
    expect(selectionMillimetres(Rect.zero, pageWidthPt: 0, pageHeightPt: 100), isEmpty);
  });

  test('a quarter turn rotates text and a picture, not a locked one or a line', () {
    final text = TextAnnotation(Offset.zero, 'Hi', Colors.black, 12, false);
    expect(quarterTurn(text), isTrue);
    expect(text.rotation, closeTo(1.5708, 0.001));
    quarterTurn(text);
    quarterTurn(text);
    quarterTurn(text);
    expect(text.rotation, closeTo(0, 0.001));

    final image = ImageAnnotation(pos: Offset.zero, width: 0.2, height: 0.2, bytes: Uint8List(0));
    expect(quarterTurn(image), isTrue);
    image.locked = true;
    expect(quarterTurn(image), isFalse);

    final line = ShapeAnnotation(ShapeType.line, Offset.zero, const Offset(0.2, 0.1), Colors.black, 1);
    expect(canQuarterTurn(line), isFalse);
  });

  testWidgets('the status bar shows the page and reports zoom, fit, lock and rotate', (tester) async {
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [...AppLocalizations.localizationsDelegates, ...kurdishFallbackDelegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EditorStatusBar(
          page: '3 / 12',
          detail: 'A4 · 210 × 297 mm',
          zoom: 125,
          onZoomIn: () => actions.add('in'),
          onZoomOut: () => actions.add('out'),
          onFit: () => actions.add('fit'),
          onToggleLock: () => actions.add('lock'),
          onRotate: () => actions.add('turn'),
        ),
      ),
    ));
    expect(find.text('3 / 12'), findsOneWidget);
    expect(find.text('A4 · 210 × 297 mm'), findsOneWidget);
    expect(find.text('125%'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.tap(find.byTooltip('Fit page'));
    await tester.tap(find.byTooltip('Lock'));
    await tester.tap(find.byTooltip('Rotate'));
    expect(actions, ['in', 'out', 'fit', 'lock', 'turn']);
  });
}
