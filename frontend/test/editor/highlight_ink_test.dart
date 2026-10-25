import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/editor_tap_tool_service.dart';

void main() {
  test('a highlight this dark or this pale is not a usable marker', () {
    expect(isPoorHighlightColor(Colors.black), isTrue);
    expect(isPoorHighlightColor(Colors.white), isTrue);
    expect(isPoorHighlightColor(const Color(0xFFFFEB3B)), isFalse);
    expect(isPoorHighlightColor(Colors.red), isFalse);
    expect(isPoorHighlightColor(Colors.blue), isFalse);
    expect(visibleHighlightColor(Colors.black), const Color(0xFFFFEB3B));
    expect(visibleHighlightColor(Colors.white), const Color(0xFFFFEB3B));
    expect(visibleHighlightColor(const Color(0xFFFFEB3B)), const Color(0xFFFFEB3B));
    expect(visibleHighlightColor(Colors.red), Colors.red);
  });
}
