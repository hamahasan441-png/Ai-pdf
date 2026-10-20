import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/data/image_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/acro_form_layer.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_selection_overlay.dart';

void main() {
  /// Asserts that no field container in the tree uses the old selection
  /// blue as a border colour (the pre-redesign AcroFormLayer look).
  void expectNoOldBlueFrame(WidgetTester tester) {
    const oldBlue = Color(0xFF5B7FD9);
    for (final c in tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer))) {
      final d = c.decoration;
      if (d is BoxDecoration && d.border != null) {
        expect(d.border!.top.color, isNot(oldBlue),
            reason: 'field frames must stay hairline graphite, never blue');
        expect(d.border!.bottom.color, isNot(oldBlue));
      }
    }
  }

  group('AcroFormLayer: no selection decorations on native fields', () {
    final form = AcroFormSnapshot.read(File('test/fixtures/pdf/forms.pdf').readAsBytesSync());
    List<PlacedAcroWidget> page0() => [
          for (final f in form.fields)
            for (final w in f.widgets)
              if (w.pageIndex == 0) (field: f, widget: w, rect: form.rectOf(w)),
        ];

    Future<void> pump(
      WidgetTester tester, {
      String? focusName,
      int? focusObjNum,
    }) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Center(
          child: SizedBox(
            width: 595,
            height: 842,
            child: AcroFormLayer(
              widgets: page0(),
              edits: const {},
              interactive: true,
              focusName: focusName,
              focusObjNum: focusObjNum,
              onTap: (_, __) {},
            ),
          ),
        ),
      ));
    }

    testWidgets('a focused field draws no dashed ring and no blue frame', (tester) async {
      await pump(tester, focusName: 'name', focusObjNum: form.fields.firstWhere((f) => f.name == 'name').widgets.first.objNum);
      // The dashed focus ring used to be a CustomPaint inside the layer;
      // none may remain under the form layer (Material itself uses some).
      expect(
        find.descendant(of: find.byType(AcroFormLayer), matching: find.byType(CustomPaint)),
        findsNothing,
        reason: 'the focused field must not draw a dashed outline',
      );
      // No container may carry the old selection blue as a border colour.
      expectNoOldBlueFrame(tester);
    });

    testWidgets('plain (unfocused) fields have no blue frame either', (tester) async {
      await pump(tester);
      expectNoOldBlueFrame(tester);
    });

    testWidgets('focusing still works: the tap handler fires', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Center(
          child: SizedBox(
            width: 595,
            height: 842,
            child: AcroFormLayer(
              widgets: page0(),
              edits: const {},
              interactive: true,
              onTap: (_, __) => taps++,
            ),
          ),
        ),
      ));
      final f = form.fields.firstWhere((f) => f.name == 'name');
      final r = form.rectOf(f.widgets.first);
      final box = tester.getRect(find.byType(AcroFormLayer));
      await tester.tapAt(box.topLeft + Offset(r.center.dx * box.width, r.center.dy * box.height));
      expect(taps, 1, reason: 'fields remain tappable without the old frame');
    });
  });

  group('EditorCanvas: selection chrome appears only in transform mode', () {
    /// Builds a canvas over one placed field. Returns the canvas and the
    /// field annotation so tests can pass it as the selection.
    (EditorCanvas, FormFieldAnnotation) buildCanvas({required bool transformMode, bool withSelection = true}) {
      final field = FormFieldAnnotation(
        pos: const Offset(0.3, 0.3),
        width: 0.3,
        height: 0.04,
        fieldKind: FormFieldKind.text,
        label: 'Name',
      );
      final layer = PageLayer()..fields.add(field);
      return (
        EditorCanvas(
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
        tool: EditTool.pan,
        layer: layer,
        drawing: const [],
        shapeStart: null,
        shapeEnd: null,
        previewShapeType: null,
        color: Colors.black,
        stroke: 2,
        highlightPreview: false,
        showFields: false,
        pageFields: const [],
        showEditLines: false,
        editLines: const [],
        guideX: null,
        guideY: null,
        multi: const {},
        selMode: 'none',
        marqueeStart: null,
        marqueeEnd: null,
        selected: withSelection ? field : null,
        boundsOf: (a) => a.bounds,
        imageRenderer: ImageAnnotationRenderer(),
        stampRenderer: const StampAnnotationRenderer(),
        transformMode: transformMode,
        onToggleTransform: () {},
        onTapUp: (_, __) {},
        onPanStart: (_, __) {},
        onPanUpdate: (_, __) {},
        onPanEnd: () {},
        onFieldTap: (_) {},
        onEditLineTap: (_) {},
        onEditText: (_) {},
        onSelectText: (_) {},
        onMoveText: (_, __, ___) {},
        onResizeBounds: (_) {},
        onTextDecrease: () {},
        onTextIncrease: () {},
        onPickTextColor: () {},
        onEditShapeStyle: () {},
        onCopySelected: () {},
        onDuplicateSelected: () {},
        onBringToFront: () {},
        onSendToBack: () {},
        onDeleteSelected: () {},
        onDeselectSelected: () {},
        onAlignMulti: (_) {},
        onDistributeMulti: (_) {},
        onDuplicateMulti: () {},
        onDeleteMulti: () {},
        onDeselectMulti: () {},
        resolveTypeIcon: (_) => Icons.short_text,
      ),
        field,
      );
    }

    Future<void> pumpCanvas(WidgetTester tester, EditorCanvas canvas) async {
      // Pump once with a plain body so the previous test's tree is fully
      // torn down, then with the real canvas.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: SizedBox(width: 400, height: 600, child: canvas))),
      ));
    }

    testWidgets('plain selection shows the contextual bar but NO box or handles', (tester) async {
      final (canvas, field) = buildCanvas(transformMode: false);
      await pumpCanvas(tester, canvas);
      expect(find.byType(EditorSelectionActionBar), findsOneWidget,
          reason: 'the compact contextual bar is the selection cue');
      expect(find.byType(EditorSelectionBox), findsNothing,
          reason: 'no bounding box on a plain selection');
      expect(find.byType(EditorScaleHandle), findsNothing,
          reason: 'no resize handles on a plain selection');
      expect(find.byType(EditorRotateHandle), findsNothing,
          reason: 'no rotate handle on a plain selection');
      expect(field, isNotNull);
    });

    testWidgets('transform mode reveals the box and the two resize handles', (tester) async {
      final (canvas, _) = buildCanvas(transformMode: true);
      await pumpCanvas(tester, canvas);
      expect(find.byType(EditorSelectionBox), findsOneWidget);
      expect(find.byType(EditorScaleHandle), findsNWidgets(2));
    });

    testWidgets('nothing selected: no selection chrome at all, even in transform mode', (tester) async {
      final (canvas, _) = buildCanvas(transformMode: true, withSelection: false);
      await pumpCanvas(tester, canvas);
      expect(find.byType(EditorSelectionBox), findsNothing);
      expect(find.byType(EditorScaleHandle), findsNothing);
      expect(find.byType(EditorSelectionActionBar), findsNothing);
    });
  });

  group('Placed fields: quiet defaults and legacy migration', () {
    test('new fields default to the neutral on-paper style, not blue', () {
      final f = FormFieldAnnotation(
        pos: const Offset(0.1, 0.1),
        width: 0.3,
        height: 0.03,
        fieldKind: FormFieldKind.text,
        label: 'x',
      );
      expect(f.borderColor, isNot(const Color(0xFF2563EB)));
      expect(f.borderColor, EditorFieldStyle.border);
      expect(f.fillColor, EditorFieldStyle.fill);
    });

    test('legacy blue fields come back with the quiet style after a round trip', () {
      final legacy = {
        'type': 'field',
        'id': 'f1',
        'posX': 0.1,
        'posY': 0.2,
        'width': 0.3,
        'height': 0.04,
        'kind': 'text',
        'label': 'Name',
        'value': '',
        'required': false,
        'checked': false,
        'options': <String>[],
        'multiline': false,
        'borderColor': EditorFieldStyle.legacyBorderArgb,
        'fillColor': EditorFieldStyle.legacyFillArgb,
        'fontSize': 0.018,
        'visible': true,
        'locked': false,
      };
      final json = {
        'version': 1,
        'pages': {
          '0': [legacy],
        },
      };
      final layers = layersFromJson(json);
      final field = layers[0]!.fields.single;
      expect(field.borderColor, EditorFieldStyle.border,
          reason: 'the old selection-blue frame migrates to the neutral hairline');
      expect(field.fillColor, EditorFieldStyle.fill);
    });

    test('user-custom colours survive the migration untouched', () {
      final custom = {
        'type': 'field',
        'id': 'f2',
        'posX': 0.1,
        'posY': 0.2,
        'width': 0.3,
        'height': 0.04,
        'kind': 'text',
        'label': 'Name',
        'value': '',
        'required': false,
        'checked': false,
        'options': <String>[],
        'multiline': false,
        'borderColor': 0xFF8B5E3C, // a deliberate brown, not the legacy default
        'fillColor': 0xFFFFF8E1,
        'fontSize': 0.018,
        'visible': true,
        'locked': false,
      };
      final layers = layersFromJson({
        'version': 1,
        'pages': {
          '0': [custom],
        },
      });
      final field = layers[0]!.fields.single;
      expect(field.borderColor, const Color(0xFF8B5E3C));
      expect(field.fillColor, const Color(0xFFFFF8E1));
    });
  });
}
