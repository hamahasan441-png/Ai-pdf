import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/presentation/widgets/editor_document_viewport.dart';
import 'package:ai_pdf/features/viewer/presentation/reading_mode_controller.dart';

/// Applies a 4×5 colour matrix to an opaque RGB colour, as the engine does.
List<int> apply(List<double> m, List<int> rgb) => [
      for (var row = 0; row < 3; row++)
        (m[row * 5] * rgb[0] + m[row * 5 + 1] * rgb[1] + m[row * 5 + 2] * rgb[2] + m[row * 5 + 4])
            .round()
            .clamp(0, 255),
    ];

List<double> matrixOf(ReadingMode mode) {
  // ColorFilter.matrix keeps its list; read it back through toString.
  final s = ReadingModeState(mode: mode).colorFilter.toString();
  return RegExp(r'-?\d+(\.\d+)?').allMatches(s.substring(s.indexOf('['))).map((m) => double.parse(m[0]!)).toList();
}

void main() {
  test('dark mode turns paper black and text white but keeps colours', () {
    final m = matrixOf(ReadingMode.dark);
    expect(m, hasLength(20));
    expect(apply(m, [255, 255, 255]), [0, 0, 0]);
    expect(apply(m, [0, 0, 0]), [255, 255, 255]);
    final red = apply(m, [220, 30, 30]);
    expect(red[0], greaterThan(red[1] + 60), reason: 'a red mark stays red, not cyan: $red');
    final blue = apply(m, [30, 60, 220]);
    expect(blue[2], greaterThan(blue[0] + 60), reason: 'blue stays blue: $blue');
  });

  testWidgets('the viewport filters the page only when a mode is set', (tester) async {
    Future<void> pump(ColorFilter? f) => tester.pumpWidget(MaterialApp(
          home: Stack(children: [
            EditorDocumentViewport(
              panEnabled: true,
              scaleEnabled: true,
              viewFilter: f,
              child: const ColoredBox(color: Colors.white),
            ),
          ]),
        ));
    await pump(null);
    expect(find.byType(ColorFiltered), findsNothing);
    await pump(ReadingModeState(mode: ReadingMode.dark).colorFilter);
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(ReadingModeState(mode: ReadingMode.normal).colorFilter, isNull);
  });
}
