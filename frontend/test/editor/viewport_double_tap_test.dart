import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/presentation/widgets/editor_document_viewport.dart';

Future<TransformationController> pumpViewport(WidgetTester tester, {required bool pan}) async {
  final controller = TransformationController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Stack(children: [
        EditorDocumentViewport(
          panEnabled: pan,
          scaleEnabled: true,
          transformationController: controller,
          child: const ColoredBox(color: Colors.white),
        ),
      ]),
    ),
  ));
  return controller;
}

Future<void> doubleTap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(at);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('double-tap zooms in around the point, and again back to the page', (tester) async {
    final c = await pumpViewport(tester, pan: true);
    const at = Offset(300, 200);
    await doubleTap(tester, at);
    expect(c.value.getMaxScaleOnAxis(), closeTo(2.5, 1e-9));
    // The tapped point stays under the finger.
    final viewportTopLeft = tester.getTopLeft(find.byType(InteractiveViewer));
    final local = at - viewportTopLeft;
    expect((MatrixUtils.transformPoint(c.value, c.toScene(local)) - local).distance, lessThan(1e-6));
    expect(c.toScene(local).dx, closeTo(local.dx, 1e-6), reason: 'zoom centred on the tap');

    await doubleTap(tester, at);
    expect(c.value, Matrix4.identity());
  });

  testWidgets('no double-tap zoom while a drawing tool is active', (tester) async {
    final c = await pumpViewport(tester, pan: false);
    await doubleTap(tester, const Offset(300, 200));
    expect(c.value, Matrix4.identity());
  });
}
