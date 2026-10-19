import 'package:flutter/material.dart';

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/editor/data/edit_capability.dart';
import 'package:ai_pdf/features/editor/data/pdf_unicode_fonts.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/data/text_style_match.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/text_selection_service.dart';

class ExistingLineEditDraft {
  final ShapeAnnotation whiteout;
  final TextAnnotation textBox;

  const ExistingLineEditDraft({required this.whiteout, required this.textBox});
}

/// Replacement of existing text: a whiteout and a new text box that copies
/// the styles we can actually read (font, size, weight, slant, direction and
/// fill colour). A missing font is a substitute, not the
/// original face.
///
/// For words of the PDF's own text ([draftForWords]) the whiteout is marked
/// [eraseTextKey]: the export removes those glyphs from the page content.
/// For OCR lines of a scanned page ([draftForLine]) there is no text to
/// remove; the whiteout covers the image as before.
class EditorExistingTextService {
  const EditorExistingTextService();

  ExistingLineEditDraft draftForLine(
    OcrLine line, {
    Set<String> loadedFamilies = const {},
  }) {
    final size = line.h * 0.72;
    final rtl = PdfUnicodeFonts.scriptOf(line.text) == EmbeddedScript.arabic ||
        PdfUnicodeFonts.scriptOf(line.text) == EmbeddedScript.hebrew;
    final family = rtl
        ? (PdfUnicodeFonts.scriptOf(line.text) == EmbeddedScript.hebrew
            ? 'NotoSansHebrew'
            : 'NotoSansArabic')
        : null;
    final kind = family != null && loadedFamilies.contains(family)
        ? FontMatchKind.exactFamily
        : (family == null ? FontMatchKind.unknown : FontMatchKind.namedSubstitute);
    final draft = ExistingLineEditDraft(
      whiteout: ShapeAnnotation(
        ShapeType.whiteout,
        Offset(line.x, line.y),
        Offset(line.x + line.w, line.y + line.h),
        Colors.white,
        1,
      ),
      textBox: TextAnnotation(
        Offset(line.x, line.y + line.h * 0.1),
        line.text.trim(),
        Colors.black,
        size.isFinite && size > 0 ? size : 0.04,
        false,
        fontFamily: family,
        textDirection: rtl ? TextDirection.rtl : null,
      ),
    );
    _labelOverlay(draft, fontKind: kind, bundledFaceLoaded: kind == FontMatchKind.exactFamily);
    return draft;
  }

  /// Overlay-only. [PdfEditCapability.nativeContentRewrite] is false on this
  /// stack even when the family name matches a bundled face.
  PdfEditCapability capabilityForLine(
    OcrLine line, {
    Set<String> loadedFamilies = const {},
  }) {
    final draft = draftForLine(line, loadedFamilies: loadedFamilies);
    return PdfEditCapability(
      fontKind: _kindOf(draft),
      bundledFaceLoaded: draft.textBox.metadata['fontFileLoaded'] == true,
    );
  }

  /// Cover the selected PDF words and open one replacement box.
  ///
  /// Words that do not share a style become separate [TextRun]s. The base
  /// size stays the first word's size so a single-style selection is unchanged.
  /// An empty list returns an empty draft instead of throwing.
  ExistingLineEditDraft draftForWords(
    List<PdfTextElement> words, {
    double pageHeightPt = 0,
    Set<String> loadedFamilies = const {},
  }) {
    if (words.isEmpty) {
      final draft = ExistingLineEditDraft(
        whiteout: ShapeAnnotation(
          ShapeType.whiteout,
          Offset.zero,
          Offset.zero,
          Colors.white,
          1,
        ),
        textBox: TextAnnotation(Offset.zero, '', Colors.black, 0.04, false),
      );
      _labelOverlay(draft, fontKind: FontMatchKind.unknown, bundledFaceLoaded: false);
      return draft;
    }
    const matcher = TextStyleMatcher();
    final styles = [
      for (final word in words)
        matcher.match(word, pageHeightPt: pageHeightPt, loadedFamilies: loadedFamilies),
    ];
    final base = styles.first;
    // The PDF's own fill colour when the extractor could read it.
    final baseColor = words.first.color ?? Colors.black;
    final multi = styles.any((style) => !_sameStyle(base, style)) ||
        words.any((word) => (word.color ?? Colors.black) != baseColor);

    var left = words.first.rect.left;
    var top = words.first.rect.top;
    var right = words.first.rect.right;
    var bottom = words.first.rect.bottom;
    final buffer = StringBuffer();
    final runs = <TextRun>[];
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final style = styles[i];
      var gap = '';
      if (i > 0) {
        gap = TextSelectionService.sameVisualLine(words[i - 1].rect, word.rect) ? ' ' : '\n';
        buffer.write(gap);
      }
      buffer.write(word.text);
      if (multi) {
        if (gap.isNotEmpty && runs.isNotEmpty) {
          final prev = runs.removeLast();
          runs.add(_copyRun(prev, prev.text + gap));
        }
        runs.add(TextRun(
          word.text,
          bold: style.bold == base.bold ? null : style.bold,
          italic: style.italic == base.italic ? null : style.italic,
          fontFamily: style.editorFamily == base.editorFamily ? null : style.editorFamily,
          sizeScale: _sizeScale(base, style),
          color: (word.color ?? Colors.black) == baseColor ? null : word.color ?? Colors.black,
        ));
      }
      if (word.rect.left.isFinite && word.rect.left < left) left = word.rect.left;
      if (word.rect.top.isFinite && word.rect.top < top) top = word.rect.top;
      if (word.rect.right.isFinite && word.rect.right > right) right = word.rect.right;
      if (word.rect.bottom.isFinite && word.rect.bottom > bottom) bottom = word.rect.bottom;
    }
    final draft = ExistingLineEditDraft(
      // These words are the PDF's own text: the export removes their glyphs
      // instead of covering them (eraseTextKey).
      whiteout: ShapeAnnotation(
        ShapeType.whiteout,
        Offset(left, top),
        Offset(right, bottom),
        Colors.white,
        1,
      )..metadata[eraseTextKey] = true,
      textBox: TextAnnotation(
        Offset(left, top),
        buffer.toString(),
        baseColor,
        base.normalizedSize > 0 ? base.normalizedSize : 0.04,
        base.bold,
        italic: base.italic,
        fontFamily: base.editorFamily,
        textDirection: base.direction,
        textAlign: base.direction == TextDirection.rtl ? TextAlign.right : TextAlign.left,
        runs: multi ? runs : null,
      ),
    );
    _labelOverlay(
      draft,
      fontKind: base.kind,
      bundledFaceLoaded: base.kind == FontMatchKind.exactFamily,
    );
    return draft;
  }

  PdfEditCapability capabilityForWords(
    List<PdfTextElement> words, {
    double pageHeightPt = 0,
    Set<String> loadedFamilies = const {},
  }) {
    final draft = draftForWords(
      words,
      pageHeightPt: pageHeightPt,
      loadedFamilies: loadedFamilies,
    );
    return PdfEditCapability(
      fontKind: _kindOf(draft),
      bundledFaceLoaded: draft.textBox.metadata['fontFileLoaded'] == true,
    );
  }

  void _labelOverlay(
    ExistingLineEditDraft draft, {
    required FontMatchKind fontKind,
    required bool bundledFaceLoaded,
  }) {
    for (final item in [draft.whiteout, draft.textBox]) {
      item.metadata['editMode'] = PdfEditMode.overlayReplacement.name;
      item.metadata['nativeContentRewrite'] = false;
      item.metadata['fontMatch'] = fontKind.name;
      item.metadata['fontFileLoaded'] = bundledFaceLoaded;
    }
  }

  FontMatchKind _kindOf(ExistingLineEditDraft draft) {
    final name = draft.textBox.metadata['fontMatch'];
    for (final kind in FontMatchKind.values) {
      if (kind.name == name) return kind;
    }
    return FontMatchKind.unknown;
  }

  bool _sameStyle(RecognizedTextStyle a, RecognizedTextStyle b) {
    if (a.bold != b.bold || a.italic != b.italic || a.editorFamily != b.editorFamily) {
      return false;
    }
    if (a.direction != b.direction) return false;
    if (a.fontSizePt > 0 && b.fontSizePt > 0) {
      return (a.fontSizePt - b.fontSizePt).abs() < 0.51;
    }
    return (a.normalizedSize - b.normalizedSize).abs() < 0.004;
  }

  double? _sizeScale(RecognizedTextStyle base, RecognizedTextStyle style) {
    double? scale;
    if (base.fontSizePt > 0 && style.fontSizePt > 0) {
      scale = style.fontSizePt / base.fontSizePt;
    } else if (base.normalizedSize > 0 && style.normalizedSize > 0) {
      scale = style.normalizedSize / base.normalizedSize;
    }
    if (scale == null || !scale.isFinite || (scale - 1).abs() < 0.04) return null;
    return scale;
  }

  TextRun _copyRun(TextRun run, String text) {
    return TextRun(
      text,
      bold: run.bold,
      italic: run.italic,
      underline: run.underline,
      color: run.color,
      fontFamily: run.fontFamily,
      sizeScale: run.sizeScale,
    );
  }
}
