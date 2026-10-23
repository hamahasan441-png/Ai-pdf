import 'dart:ui' show Color, Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/data/text_markup_factory.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/domain/entities/text_markup_annotation.dart';

PdfTextElement _el(String text, double left, double top) => PdfTextElement(
      text: text,
      rect: Rect.fromLTWH(left, top, 0.15, 0.03),
      fontSize: 12,
    );

void main() {
  const factory = TextMarkupFactory();
  const yellow = Color(0xFFFFEB3B);

  final elements = [
    _el('Hello', 0.10, 0.10),
    _el('World', 0.30, 0.10),
    _el('Foo', 0.10, 0.20),
  ];

  test('a drag across words snaps the mark to those glyphs', () {
    final mark = factory.fromDrag(
      tool: EditTool.underline,
      start: const Offset(0.12, 0.11),
      end: const Offset(0.32, 0.11),
      elements: elements,
      color: yellow,
    );
    expect(mark, isNotNull);
    expect(mark!.kind, TextMarkupKind.underline);
    expect(mark.text, 'Hello World');
    expect(mark.rects, hasLength(2));
  });

  test('highlight, strikeout and squiggly share the same word range', () {
    for (final tool in [EditTool.highlight, EditTool.strikeout, EditTool.squiggly]) {
      final mark = factory.fromDrag(
        tool: tool,
        start: const Offset(0.12, 0.11),
        end: const Offset(0.12, 0.21),
        elements: elements,
        color: yellow,
      );
      expect(mark!.kind, factory.kindFor(tool));
      expect(mark.text, 'Hello World\nFoo');
    }
  });

  test('a tap inside a word selects only that word', () {
    final sel = factory.wordsBetween(
      start: const Offset(0.12, 0.11),
      end: const Offset(0.12, 0.11),
      elements: elements,
    );
    expect(sel, isNotNull);
    expect(sel!.text, 'Hello');
    expect(factory.containsText(elements, const Offset(0.12, 0.11)), isTrue);
    expect(factory.containsText(elements, const Offset(0.01, 0.01)), isFalse);
    final mark = factory.fromSelection(
      tool: EditTool.strikeout,
      selection: sel,
      color: yellow,
    );
    expect(mark!.kind, TextMarkupKind.strikeout);
    expect(mark.text, 'Hello');
  });

  test('a scanned page uses the drag rectangle', () {
    final mark = factory.fromDrag(
      tool: EditTool.highlight,
      start: const Offset(0.70, 0.40),
      end: const Offset(0.20, 0.20),
      elements: const [],
      color: yellow,
    );
    expect(mark, isNotNull);
    expect(mark!.rects, hasLength(1));
    expect(mark.rects.single.left, closeTo(0.20, 0.001));
    expect(mark.rects.single.top, closeTo(0.20, 0.001));
    expect(mark.rects.single.right, closeTo(0.70, 0.001));
    expect(mark.rects.single.bottom, closeTo(0.40, 0.001));
  });

  test('a tap with no text layer does not create a mark', () {
    final mark = factory.fromDrag(
      tool: EditTool.squiggly,
      start: const Offset(0.40, 0.40),
      end: const Offset(0.402, 0.401),
      elements: const [],
      color: yellow,
    );
    expect(mark, isNull);
  });

  test('draw is not a text-markup tool', () {
    expect(factory.isMarkupTool(EditTool.draw), isFalse);
    expect(
      factory.fromDrag(
        tool: EditTool.draw,
        start: Offset.zero,
        end: const Offset(0.5, 0.5),
        elements: elements,
        color: yellow,
      ),
      isNull,
    );
  });
}
