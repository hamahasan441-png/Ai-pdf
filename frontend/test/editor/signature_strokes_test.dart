import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_pdf/core/services/signature_store.dart';
import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/data/editor_hit_test_service.dart';
import 'package:ai_pdf/features/editor/data/editor_signature_insert_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/signature_pad_sheet.dart';

void main() {
  // Two strokes: a line on the left, then (pen lifted) a line on the right.
  const pad = [
    Offset(0, 0), Offset(10, 0), Offset.infinite, //
    Offset(90, 0), Offset(100, 0), Offset.infinite,
  ];

  test('pad output splits into points and stroke starts', () {
    final s = StrokeAnnotation.splitStrokes(pad);
    expect(s.points, const [Offset(0, 0), Offset(10, 0), Offset(90, 0), Offset(100, 0)]);
    expect(s.breaks, [2]);
    expect(StrokeAnnotation.splitStrokes(const [Offset.infinite, Offset(1, 1), Offset(2, 2)]).breaks, isEmpty);
  });

  test('a placed signature keeps its strokes apart, also when hit and saved', () {
    final sig = const EditorSignatureInsertService().signatureFromPadPoints(pad);
    expect(sig.points.length, 4);
    expect(sig.breaks, [2]);

    // The gap between the strokes is not ink.
    final layer = PageLayer()..items.add(sig);
    final gap = Offset.lerp(sig.points[1], sig.points[2], 0.5)!;
    expect(const EditorHitTestService().strokeNear(layer, gap, slop: 0.01), isNull);
    expect(const EditorHitTestService().strokeNear(layer, sig.points[0], slop: 0.01), same(sig));

    final back = annotationFromJson(jsonDecode(jsonEncode(annotationToJson(sig))) as Map<String, dynamic>)!
        as StrokeAnnotation;
    expect(back.breaks, [2]);
    expect(sig.clone().breaks, [2]);
  });

  test('saved signatures keep their pen lifts', () async {
    SharedPreferences.setMockInitialValues({});
    await SignatureStore.instance.save([pad.toList()]);
    final loaded = await SignatureStore.instance.load();
    expect(loaded.single.where((p) => !p.isFinite).length, 2);
    expect(StrokeAnnotation.splitStrokes(loaded.single).breaks, [2]);
  });

  testWidgets('the pad returns nothing until something is drawn, then every stroke', (tester) async {
    List<Offset>? result;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<Offset>>(
              MaterialPageRoute(builder: (_) => const SignaturePadSheet()),
            );
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Done')).onPressed, isNull);

    final pad = tester.getCenter(find.byKey(const ValueKey('signaturePad')));
    await tester.dragFrom(pad, const Offset(60, 0));
    await tester.dragFrom(pad + const Offset(0, 40), const Offset(60, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(StrokeAnnotation.splitStrokes(result!).breaks.length, 1, reason: 'two strokes');
  });
}
