import 'dart:math' as math;

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// Builds the plain text of a document from its positioned text layer.
///
/// Used by the document comparison feature: the diff needs the same reading
/// order for both versions, and the positioned layer (page order → line
/// bands → left-to-right inside a line) provides it deterministically.
///
/// Lines are grouped by vertical centre with a tolerance derived from the
/// element's own height, so slightly rotated text and sub/superscripts stay
/// on their line instead of being scattered.
String plainTextFromTextLayer(Map<int, List<PdfTextElement>> pages) {
  final pageKeys = pages.keys.toList()..sort();
  final out = <String>[];
  for (final key in pageKeys) {
    final text = _pageText(pages[key] ?? const []);
    if (text.isNotEmpty) out.add(text);
  }
  return out.join('\n\n');
}

/// The plain text of one page's text layer, in reading order.
String plainTextOfPage(List<PdfTextElement> elements) => _pageText(elements);

/// Arabic-script and Hebrew letters: a line made mostly of them reads from
/// right to left.
final _rtlLetter = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final _anyLetter = RegExp(r'[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');

bool _rightToLeft(List<PdfTextElement> line) {
  final text = line.map((e) => e.text).join();
  final letters = _anyLetter.allMatches(text).length;
  return letters > 0 && _rtlLetter.allMatches(text).length * 2 > letters;
}

String _pageText(List<PdfTextElement> elements) {
  final words = elements.where((e) => e.text.trim().isNotEmpty).toList()
    ..sort((a, b) {
      final byY = a.rect.center.dy.compareTo(b.rect.center.dy);
      if (byY != 0) return byY;
      return a.rect.center.dx.compareTo(b.rect.center.dx);
    });
  if (words.isEmpty) return '';

  final lines = <List<PdfTextElement>>[];
  var current = <PdfTextElement>[words.first];
  var bandTop = words.first.rect.center.dy;
  var bandHalf = _halfHeight(words.first);
  for (var i = 1; i < words.length; i++) {
    final e = words[i];
    final centre = e.rect.center.dy;
    // The band must accept a smaller raised glyph (superscript) next to a
    // taller base word, so the tolerance follows the TALLER of the two.
    final tolerance = math.max(bandHalf, _halfHeight(e));
    if ((centre - bandTop).abs() <= tolerance) {
      current.add(e);
      // Recentre the band so a long line with drift stays together.
      bandTop = (bandTop * (current.length - 1) + centre) / current.length;
    } else {
      lines.add(current);
      current = <PdfTextElement>[e];
      bandTop = centre;
      bandHalf = _halfHeight(e);
    }
  }
  lines.add(current);

  final buffer = StringBuffer();
  for (final line in lines) {
    // Kurdish, Arabic and Persian lines read from right to left.
    final rtl = _rightToLeft(line);
    line.sort((a, b) => rtl ? b.rect.center.dx.compareTo(a.rect.center.dx) : a.rect.center.dx.compareTo(b.rect.center.dx));
    buffer.writeln(line.map((e) => e.text.trim()).join(' '));
  }
  return buffer.toString().trimRight();
}

double _halfHeight(PdfTextElement e) {
  // Half the element's own height: two glyph boxes belong to one line while
  // their vertical centres sit within that reach of each other. A floor
  // keeps degenerate (zero-height) boxes from forming their own line.
  final h = e.rect.height * 0.5;
  return h <= 0 ? 0.005 : h;
}
