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
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Off-screen export compositor for the editor.
///
/// Re-renders each page at a high pixel cap, composites editor annotations onto
/// an off-screen canvas, then writes a flattened PDF. Latin-1 text is overlaid
/// as real vector text; non-Latin text and special mark glyphs are rasterized
/// into the page image so they always render correctly.
class EditorExportService {
  static const double exportMaxEdge = 1800;

  const EditorExportService();

  Future<String?> renderToPdfFile({
    required pdfx.PdfDocument? doc,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    required int pageCount,
  }) async {
    final pdf = pw.Document();
    final fonts = EditorPdfFonts();
    var rendered = 0;

    for (var i = 0; i < pageCount; i++) {
      final composed = await _composePagePng(
        index: i,
        doc: doc,
        pageCache: pageCache,
        layers: layers,
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
          .where((t) => t.text.isNotEmpty && _isLatin1(t.text))
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
                  pw.Positioned(
                    left: t.pos.dx * pageW,
                    top: t.pos.dy * pageH,
                    child: pw.SizedBox(
                      width: (pageW * (1 - t.pos.dx)).clamp(1.0, pageW),
                      child: pw.Text(
                        t.text,
                        style: pw.TextStyle(
                          font: fonts.pick(t.fontFamily, t.bold, t.italic),
                          fontSize: t.size * pageH,
                          color: PdfColor.fromInt(t.color.value),
                          decoration: t.underline
                              ? pw.TextDecoration.underline
                              : pw.TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
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

  Future<({Uint8List bytes, int width, int height})?> _composePagePng({
    required int index,
    required pdfx.PdfDocument? doc,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
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
        for (final s in layer.strokes) {
          AnnotationDraw.stroke(canvas, size, s.points, s.color, s.width);
        }
        for (final s in layer.shapes) {
          if (s.type == ShapeType.rect || s.type == ShapeType.whiteout) {
            continue;
          }
          AnnotationDraw.shape(canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
        }
        for (final t in layer.texts) {
          if (!_isLatin1(t.text)) {
            AnnotationDraw.text(canvas, size, t);
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
