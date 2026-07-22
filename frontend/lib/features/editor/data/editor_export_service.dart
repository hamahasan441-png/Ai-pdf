import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:ai_pdf/features/editor/data/annotation_draw.dart';
import 'package:ai_pdf/features/editor/data/editor_pdf_fonts.dart';
import 'package:ai_pdf/features/editor/data/pdf_unicode_fonts.dart';
import 'package:ai_pdf/features/editor/data/rtl_text_renderer.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/services/rtl_detection_service.dart';

/// Off-screen export compositor for the editor.
///
/// Re-renders each page at a high pixel cap, composites editor annotations onto
/// an off-screen canvas, then writes a flattened PDF. Latin-1 text is overlaid
/// as real vector text; non-Latin text and special mark glyphs are rasterized
/// into the page image so they always render correctly.
class EditorExportService {
  static const double exportMaxEdge = 1800;

  static const StampAnnotationRenderer _stampRenderer = StampAnnotationRenderer();
  static const RtlTextRenderer _rtlText = RtlTextRenderer();

  const EditorExportService();

  Future<String?> renderToPdfFile({
    required pdfx.PdfDocument? doc,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    required int pageCount,
  }) async {
    final pdf = pw.Document();
    final fonts = EditorPdfFonts();
    // Load bundled Unicode fonts (if present) so RTL text can be exported as
    // searchable vector text instead of a rasterized image.
    final uni = PdfUnicodeFonts();
    await uni.load();
    const rtlDetect = RtlDetectionService();
    var rendered = 0;

    for (var i = 0; i < pageCount; i++) {
      final composed = await _composePagePng(
        index: i,
        doc: doc,
        pageCache: pageCache,
        layers: layers,
        uni: uni,
      );
      if (composed == null) {
        await Future<void>.delayed(Duration.zero);
        continue;
      }

      const longPts = 842.0;
      final double pageW, pageH;
      if (composed.width >= composed.height) {
        pageW = longPts;
        pageH = longPts * composed.height / composed.width;
      } else {
        pageH = longPts;
        pageW = longPts * composed.width / composed.height;
      }

      final image = pw.MemoryImage(composed.bytes);
      final shapes = (layers[i]?.shapes ?? const <ShapeAnnotation>[])
          .where((s) => s.type == ShapeType.rect || s.type == ShapeType.whiteout)
          .toList();
      final texts = (layers[i]?.texts ?? const <TextAnnotation>[])
          .where((t) => t.text.isNotEmpty && _canVectorize(t, uni))
          .toList();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageW, pageH, marginAll: 0),
          build: (_) => pw.SizedBox(
            width: pageW,
            height: pageH,
            child: pw.Stack(
              children: [
                pw.SizedBox(
                  width: pageW,
                  height: pageH,
                  child: pw.Image(image, fit: pw.BoxFit.fill),
                ),
                for (final s in shapes) _buildPdfShape(s, pageW, pageH),
                for (final t in texts)
                  _buildPdfText(t, pageW, pageH, fonts, uni, rtlDetect),
              ],
            ),
          ),
        ),
      );
      rendered++;
      await Future<void>.delayed(Duration.zero);
    }

    if (rendered == 0) return null;

    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await File(outPath).writeAsBytes(await pdf.save());
    return outPath;
  }

  /// Whether [t] can be exported as real (searchable) vector text: Latin-1 is
  /// always vectorizable (standard PDF fonts); other scripts require a bundled
  /// Unicode font. Multi-run rich text is kept as raster (see [_richText]) so
  /// the preview and export stay pixel-identical.
  bool _canVectorize(TextAnnotation t, PdfUnicodeFonts uni) {
    if (_richText(t)) return false;
    return _isLatin1(t.text) || uni.pick(t) != null;
  }

  /// True when the annotation carries more than one style run.
  bool _richText(TextAnnotation t) => (t.runs?.length ?? 0) > 1;

  /// Build a positioned vector-text widget, choosing a standard PDF font for
  /// Latin text and a bundled Unicode font for RTL scripts, with the correct
  /// direction and alignment so it matches the on-screen preview.
  pw.Widget _buildPdfText(
    TextAnnotation t,
    double pageW,
    double pageH,
    EditorPdfFonts fonts,
    PdfUnicodeFonts uni,
    RtlDetectionService rtlDetect,
  ) {
    final font = _isLatin1(t.text)
        ? fonts.pick(t.fontFamily, t.bold, t.italic)
        : (uni.pick(t) ?? fonts.pick(t.fontFamily, t.bold, t.italic));
    final isRtl = t.textDirection == TextDirection.rtl ||
        (t.textDirection == null && rtlDetect.isRtl(t.text));
    // RTL text with no explicit alignment defaults to right-aligned.
    final align = (t.textAlign == TextAlign.left && isRtl) ? TextAlign.right : t.textAlign;
    return pw.Positioned(
      left: t.pos.dx * pageW,
      top: t.pos.dy * pageH,
      child: pw.SizedBox(
        width: (pageW * (1 - t.pos.dx)).clamp(1.0, pageW),
        child: pw.Text(
          t.text,
          textAlign: _pwAlign(align),
          textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          style: pw.TextStyle(
            font: font,
            fontSize: t.size * pageH,
            color: PdfColor.fromInt(t.color.value),
            decoration:
                t.underline ? pw.TextDecoration.underline : pw.TextDecoration.none,
          ),
        ),
      ),
    );
  }

  /// Map the editor's [TextAlign] to the PDF widget library's equivalent so
  /// exported vector text is aligned exactly like the on-screen preview.
  pw.TextAlign _pwAlign(TextAlign a) {
    switch (a) {
      case TextAlign.center:
        return pw.TextAlign.center;
      case TextAlign.right:
      case TextAlign.end:
        return pw.TextAlign.right;
      case TextAlign.justify:
        return pw.TextAlign.justify;
      default:
        return pw.TextAlign.left;
    }
  }

  bool _isLatin1(String s) {
    for (final c in s.codeUnits) {
      if (c > 0xFF) return false;
    }
    return true;
  }

  PdfColor _pdfColor(Color c, [double opacity = 1.0]) {
    final v = c.value;
    return PdfColor(
      ((v >> 16) & 0xFF) / 255.0,
      ((v >> 8) & 0xFF) / 255.0,
      (v & 0xFF) / 255.0,
      opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  pw.Widget _buildPdfShape(ShapeAnnotation s, double pageW, double pageH) {
    final left = math.min(s.start.dx, s.end.dx) * pageW;
    final top = math.min(s.start.dy, s.end.dy) * pageH;
    final w = (s.start.dx - s.end.dx).abs() * pageW;
    final h = (s.start.dy - s.end.dy).abs() * pageH;
    final k = pageH / 1000.0;
    if (s.type == ShapeType.whiteout) {
      return pw.Positioned(
        left: left,
        top: top,
        child: pw.Container(
          width: w,
          height: h,
          decoration: pw.BoxDecoration(
            color: const PdfColor(1, 1, 1),
            border: pw.Border.all(
              color: const PdfColor(0.62, 0.62, 0.62),
              width: (k).clamp(0.3, 2.0).toDouble(),
            ),
          ),
        ),
      );
    }
    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Container(
        width: w,
        height: h,
        decoration: pw.BoxDecoration(
          color: s.filled ? _pdfColor(s.color, s.opacity * 0.25) : null,
          border: pw.Border.all(
            color: _pdfColor(s.color, s.opacity),
            width: (s.width * k).clamp(0.3, 40.0).toDouble(),
          ),
        ),
      ),
    );
  }

  /// Decode and composite an [ImageAnnotation] onto the off-screen [canvas],
  /// honouring position, size and rotation (mirrors ImageAnnotationRenderer so
  /// the export matches the on-screen preview).
  Future<void> _drawImageAnnotation(Canvas canvas, Size size, ImageAnnotation ann) async {
    try {
      final codec = await ui.instantiateImageCodec(ann.bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final rect = Rect.fromLTWH(
        ann.pos.dx * size.width,
        ann.pos.dy * size.height,
        ann.width * size.width,
        ann.height * size.height,
      );
      final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      final paint = Paint()..filterQuality = FilterQuality.high;
      canvas.save();
      if (ann.rotation != 0) {
        canvas.translate(rect.center.dx, rect.center.dy);
        canvas.rotate(-ann.rotation);
        canvas.translate(-rect.width / 2, -rect.height / 2);
        canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
      } else {
        canvas.drawImageRect(img, src, rect, paint);
      }
      canvas.restore();
      img.dispose();
      codec.dispose();
    } catch (_) {
      // Skip an undecodable image rather than aborting the whole export.
    }
  }

  Future<({Uint8List bytes, int width, int height})?> _composePagePng({
    required int index,
    required pdfx.PdfDocument? doc,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    required PdfUnicodeFonts uni,
  }) async {
    Uint8List? baseBytes;
    if (doc != null) {
      final page = await doc.getPage(index + 1);
      try {
        final longEdge = page.width > page.height ? page.width : page.height;
        final scale = longEdge > exportMaxEdge ? exportMaxEdge / longEdge : 1.0;
        final img = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        baseBytes = img?.bytes;
      } finally {
        await page.close();
      }
    } else {
      baseBytes = pageCache[index];
    }
    if (baseBytes == null) return null;

    final codec = await ui.instantiateImageCodec(baseBytes);
    final frame = await codec.getNextFrame();
    final base = frame.image;

    try {
      final size = Size(base.width.toDouble(), base.height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawImage(base, Offset.zero, Paint());
      final layer = layers[index];
      if (layer != null) {
        // Background layer: images (photos / logos / scanned signatures).
        for (final im in layer.images) {
          await _drawImageAnnotation(canvas, size, im);
        }
        for (final s in layer.strokes) {
          AnnotationDraw.stroke(canvas, size, s.points, s.color, s.width);
        }
        for (final s in layer.shapes) {
          if (s.type == ShapeType.rect || s.type == ShapeType.whiteout) {
            continue;
          }
          AnnotationDraw.shape(canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
        }
        // Stamps (bordered label boxes) sit above shapes, matching the preview.
        for (final st in layer.stamps) {
          _stampRenderer.paint(canvas, size, st);
        }
        // Text that can't be exported as vector (non-Latin without a bundled
        // Unicode font, or multi-run rich text) is rasterized with full
        // RTL/BiDi handling so it still exports in the correct visual order.
        for (final t in layer.texts) {
          if (!_canVectorize(t, uni)) {
            _rtlText.paint(canvas, size, t);
          }
        }
      }
      final picture = recorder.endRecording();
      final composed = await picture.toImage(base.width, base.height);
      try {
        final data = await composed.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return null;
        return (
          bytes: data.buffer.asUint8List(),
          width: base.width,
          height: base.height,
        );
      } finally {
        composed.dispose();
        picture.dispose();
      }
    } finally {
      base.dispose();
    }
  }
}
