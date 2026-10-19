import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:ai_pdf/features/editor/data/annotation_draw.dart';
import 'package:ai_pdf/features/editor/data/editor_page_transform_service.dart';
import 'package:ai_pdf/features/editor/data/editor_pdf_fonts.dart';
import 'package:ai_pdf/features/editor/data/page_cache_policy.dart';
import 'package:ai_pdf/features/editor/data/page_structure.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/preserving_pdf_writer.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_text_eraser.dart';
import 'package:ai_pdf/features/editor/data/pdf_unicode_fonts.dart';
import 'package:ai_pdf/features/editor/data/rtl_text_renderer.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/entities/sticky_note_annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/rtl_detection_service.dart';

/// Searchable vector export is only used when it matches the preview.
/// Rotated text and multi-style runs are painted into the page image,
/// because the PDF text widget would drop the rotation and the extra runs.
bool textExportsAsSearchableVector({
  required int runCount,
  required double rotation,
  required bool latin1,
  required bool unicodeFontAvailable,
}) {
  if (rotation != 0) return false;
  if (runCount > 1) return false;
  return latin1 || unicodeFontAvailable;
}

/// A page the export needed could not be produced.
///
/// The export stops instead of writing a PDF with that page missing. The
/// message names the 1-based page and never includes document text.
class ExportPageException implements Exception {
  final int pageIndex;
  final String reason;

  const ExportPageException(this.pageIndex, this.reason);

  @override
  String toString() => 'Page ${pageIndex + 1}: $reason';
}

/// The source PDF cannot be kept as is (encrypted, damaged, or a filter
/// this reader does not support). The caller must ask before falling back
/// to an image-only export; it must not do so silently.
enum ExportUnavailableKind { unreadableFile, encrypted, damaged, writeFailed }

class PreservingExportUnavailable implements Exception {
  final String reason;
  final ExportUnavailableKind kind;

  const PreservingExportUnavailable(this.reason, [this.kind = ExportUnavailableKind.damaged]);

  @override
  String toString() => reason;
}

/// Result of [EditorExportService.renderPreservingPdfFile].
class PreservingExportResult {
  final String path;

  /// Shown page indexes saved as images because their marks hide content.
  final List<int> flattenedPages;

  final PreservingWriteReport report;

  const PreservingExportResult(this.path, this.flattenedPages, this.report);
}

/// Pages whose marks are meant to hide what is under them: a whiteout
/// (overlay text edits use one) or a black cover that the server did not
/// back with real redaction. In a source-preserving export the original text
/// would still be in the file under such a mark, so these pages are saved as
/// images instead. Hidden marks do not count.
/// [layers] with [marks] added to page [index] beneath its own marks, or
/// [layers] itself when there is nothing to add. The originals are not
/// changed.
Map<int, PageLayer> withMarksBelow(Map<int, PageLayer> layers, int index, List<EditorAnnotation>? marks) {
  if (marks == null || marks.isEmpty) return layers;
  return {...layers, index: PageLayer()..items.addAll([...marks, ...?layers[index]?.items])};
}

/// Boxes (0..1, displayed page) of the replaced PDF text on [layer]: the
/// visible whiteouts marked with [eraseTextKey].
List<List<double>> eraseRegionsOf(PageLayer? layer) => [
      for (final s in layer?.shapes ?? const <ShapeAnnotation>[])
        if (s.visible && s.type == ShapeType.whiteout && s.metadata[eraseTextKey] == true)
          [
            math.min(s.start.dx, s.end.dx),
            math.min(s.start.dy, s.end.dy),
            math.max(s.start.dx, s.end.dx),
            math.max(s.start.dy, s.end.dy),
          ],
    ];

/// Pages that must be saved as images because a mark hides content: a
/// whiteout or a burned cover. Whiteouts over replaced text are not counted
/// here; the export removes that text instead when it can.
List<int> pagesThatHideContent(Map<int, PageLayer> layers, Iterable<int> slots) {
  final out = <int>[];
  for (final i in slots) {
    final layer = layers[i];
    if (layer == null) continue;
    final hides = layer.shapes.any((s) =>
        s.visible &&
        ((s.type == ShapeType.whiteout && s.metadata[eraseTextKey] != true) ||
            (s.burnsBlackCover && !s.isServerRedacted)));
    if (hides) out.add(i);
  }
  return out;
}

/// Off-screen export compositor for the editor.
///
/// Each page is rendered to a bitmap and the marks are painted on that bitmap,
/// then the bitmap is wrapped in a new PDF. This is not an incremental edit of
/// the source file. The exported pages lose the source's text layer (so the
/// original text is not searchable or selectable), vector objects, links,
/// annotations, form fields, bookmarks and metadata. `pdf` 3.11 can only
/// create documents and `pdfx` can only render them, so neither can carry the
/// source objects across. Searchable vector text is added only for new
/// annotations that [textExportsAsSearchableVector] accepts.
///
/// [renderPreservingPdfFile] is the source-preserving path: it keeps the
/// original PDF objects and draws the marks on top (see
/// [PreservingPdfWriter]). [renderToPdfFile] is the image-only path, used for
/// image documents and when the user chooses it.
///
/// A page that fails to render, rotate, or composite throws
/// [ExportPageException]; no file is written. Earlier builds skipped such a
/// page and saved a shorter document.
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
    Map<int, int> quarterTurns = const {},
    List<int>? sourcePages,
    List<int>? onlyIndices,
  }) async {
    final pdf = pw.Document();
    final fonts = EditorPdfFonts();
    // Load bundled Unicode fonts (if present) so RTL text can be exported as
    // searchable vector text instead of a rasterized image.
    final uni = PdfUnicodeFonts();
    await uni.load();
    var rendered = 0;

    for (final i in exportSlots(pageCount: pageCount, only: onlyIndices)) {
      final composed = await _composePagePng(
        index: i,
        doc: doc,
        pageCache: pageCache,
        layers: layers,
        uni: uni,
        quarterTurns: (quarterTurns[i] ?? 0) % 4,
        sourcePage: sourcePages != null && i < sourcePages.length ? sourcePages[i] : i,
      );
      if (composed == null) {
        throw ExportPageException(i, 'the page could not be rendered');
      }

      final size = _flattenedPageSize(composed);
      _addEditedPage(
        pdf,
        pageW: size.width,
        pageH: size.height,
        image: pw.MemoryImage(composed.bytes),
        layer: layers[i],
        fonts: fonts,
        uni: uni,
      );
      rendered++;
      await Future<void>.delayed(Duration.zero);
    }

    if (rendered == 0) return null;
    return _writeAtomically(await pdf.save(), getApplicationDocumentsDirectory);
  }

  /// Export that keeps the source PDF: text stays searchable and selectable,
  /// and vectors, links, annotations, form fields, bookmarks and metadata
  /// survive. Marks are drawn on top as an overlay; vector text stays vector.
  ///
  /// Pages in [pagesThatHideContent] are saved as images, with nothing of
  /// the original page left in the file. Inserted blank pages are generated.
  /// Deleted pages and earlier revisions are not in the output.
  ///
  /// Throws [PreservingExportUnavailable] when the source cannot be kept;
  /// the caller decides with the user whether to save as images instead.
  Future<PreservingExportResult> renderPreservingPdfFile({
    required String sourcePath,
    required pdfx.PdfDocument? doc,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    required int pageCount,
    required List<int> sourcePages,
    Map<int, int> quarterTurns = const {},
    List<int>? onlyIndices,
    Future<Directory> Function()? outputDirectory,
    Map<String, Object> formValues = const {},
    Map<int, List<EditorAnnotation>> flattenedPageMarks = const {},
  }) async {
    final Uint8List sourceBytes;
    try {
      sourceBytes = await File(sourcePath).readAsBytes();
    } catch (_) {
      throw const PreservingExportUnavailable(
        'The original PDF could not be read from this device.',
        ExportUnavailableKind.unreadableFile,
      );
    }
    final slots = exportSlots(pageCount: pageCount, only: onlyIndices);
    if (slots.isEmpty) throw const PreservingExportUnavailable('Nothing to export.');
    // Replaced text whose glyphs can be removed from the page content.
    final eraseJobs = <int, (int, List<List<double>>, int)>{
      for (final i in slots)
        if (eraseRegionsOf(layers[i]) case final regions when regions.isNotEmpty)
          i: (i < sourcePages.length ? sourcePages[i] : i, regions, (quarterTurns[i] ?? 0) % 4),
    };
    final List<(List<double>, int)> sourceGeometry;
    final Set<int> erasable;
    try {
      (sourceGeometry, erasable) = await Isolate.run(() {
        final store = PdfObjectStore.parse(sourceBytes);
        final ok = <int>{
          for (final MapEntry(key: i, value: (source, regions, turns)) in eraseJobs.entries)
            if (source >= 0 &&
                source < store.pages.length &&
                erasePageText(store, store.pages[source], regions, quarterTurns: turns).complete)
              i,
        };
        return ([for (final p in store.pages) (p.cropBox, p.rotate)], ok);
      });
    } on PdfSourceException catch (e) {
      throw PreservingExportUnavailable(
        e.encrypted ? 'The PDF is encrypted.' : 'The PDF structure could not be read: ${e.message}',
        e.encrypted ? ExportUnavailableKind.encrypted : ExportUnavailableKind.damaged,
      );
    }

    // A page whose replaced text cannot be removed cleanly is flattened, as
    // a whiteout always was: its old text must not survive under the box.
    final flatten = {
      ...pagesThatHideContent(layers, slots),
      for (final i in eraseJobs.keys)
        if (!erasable.contains(i)) i,
    };

    final generated = pw.Document();
    final fonts = EditorPdfFonts();
    final uni = PdfUnicodeFonts();
    await uni.load();
    var generatedCount = 0;
    final specs = <OutputPageSpec>[];

    for (final i in slots) {
      final source = i < sourcePages.length ? sourcePages[i] : i;
      final turns = (quarterTurns[i] ?? 0) % 4;
      if (source >= sourceGeometry.length) {
        throw PreservingExportUnavailable('Page ${i + 1} points at a page the PDF does not have.');
      }
      if (source < 0 || flatten.contains(i)) {
        // A flattened page has no form any more: draw its edited values.
        final pageLayers = withMarksBelow(layers, i, flattenedPageMarks[i]);
        final composed = await _composePagePng(
          index: i,
          doc: doc,
          pageCache: pageCache,
          layers: pageLayers,
          uni: uni,
          quarterTurns: turns,
          sourcePage: source,
        );
        if (composed == null) throw ExportPageException(i, 'the page could not be rendered');
        final size = _flattenedPageSize(composed);
        _addEditedPage(
          generated,
          pageW: size.width,
          pageH: size.height,
          image: pw.MemoryImage(composed.bytes),
          layer: pageLayers[i],
          fonts: fonts,
          uni: uni,
        );
        specs.add(GeneratedPageSpec(generatedCount++, replacesSource: source < 0 ? null : source));
        await Future<void>.delayed(Duration.zero);
        continue;
      }

      final layer = layers[i];
      if (layer == null || !layer.items.any((a) => a.visible)) {
        specs.add(SourcePageSpec(source, quarterTurns: turns, eraseRegions: eraseJobs[i]?.$2 ?? const []));
        continue;
      }
      final (crop, rotate) = sourceGeometry[source];
      final finalRotate = (rotate + 90 * turns) % 360;
      final w = crop[2] - crop[0];
      final h = crop[3] - crop[1];
      final pageW = finalRotate % 180 == 0 ? w : h;
      final pageH = finalRotate % 180 == 0 ? h : w;
      // Rectangles, whiteouts and searchable text are written as vectors;
      // a page with nothing else gets no transparent full-page bitmap.
      pw.MemoryImage? marksImage;
      if (layer.items.any((a) => a.visible && !_exportsAsVector(a, uni))) {
        final scale = math.min(exportMaxEdge / math.max(pageW, pageH), 3.0);
        final marks = await _composePagePng(
          index: i,
          doc: null,
          pageCache: const {},
          layers: layers,
          uni: uni,
          marksOnlySize: Size((pageW * scale).roundToDouble(), (pageH * scale).roundToDouble()),
        );
        if (marks == null) throw ExportPageException(i, 'the marks could not be drawn');
        marksImage = pw.MemoryImage(marks.bytes);
      }
      _addEditedPage(
        generated,
        pageW: pageW,
        pageH: pageH,
        image: marksImage,
        layer: layer,
        fonts: fonts,
        uni: uni,
        // The replaced text is removed from the page; a white box would hide
        // the background (a coloured header, a table rule) for nothing.
        drawEraseCovers: false,
      );
      specs.add(SourcePageSpec(
        source,
        quarterTurns: turns,
        overlayPage: generatedCount++,
        eraseRegions: eraseJobs[i]?.$2 ?? const [],
      ));
      await Future<void>.delayed(Duration.zero);
    }

    final generatedBytes = generatedCount == 0 ? null : await generated.save();
    final (Uint8List bytes, PreservingWriteReport report) written;
    try {
      written = await Isolate.run(() {
        final source = PdfObjectStore.parse(sourceBytes);
        final gen = generatedBytes == null ? null : PdfObjectStore.parse(generatedBytes);
        final writer = PreservingPdfWriter(source, gen);
        final out = writer.write(specs, formValues: formValues);
        // Read our own output back before calling it a success.
        final check = PdfObjectStore.parse(out);
        if (check.pages.length != specs.length) {
          throw const PdfSourceException('The written PDF has the wrong number of pages.');
        }
        return (out, writer.report!);
      });
    } on PdfSourceException catch (e) {
      throw PreservingExportUnavailable(
        'The PDF could not be written with its original content: ${e.message}',
        ExportUnavailableKind.writeFailed,
      );
    }
    final path = await _writeAtomically(
      written.$1,
      outputDirectory ?? getApplicationDocumentsDirectory,
    );
    if (path == null) {
      throw const PreservingExportUnavailable(
        'The exported file could not be saved.',
        ExportUnavailableKind.writeFailed,
      );
    }
    return PreservingExportResult(path, [for (final i in slots) if (flatten.contains(i)) i], written.$2);
  }

  Future<String?> _writeAtomically(Uint8List bytes, Future<Directory> Function() dirOf) async {
    final dir = await dirOf();
    final outPath = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final partial = File('$outPath.partial');
    try {
      await partial.writeAsBytes(bytes, flush: true);
      if (partial.lengthSync() < 32) {
        await partial.delete();
        return null;
      }
      await partial.rename(outPath);
    } catch (_) {
      if (partial.existsSync()) await partial.delete();
      rethrow;
    }
    return outPath;
  }

  Size _flattenedPageSize(_ComposedPage composed) {
    const longPts = 842.0;
    if (composed.sourceWidth != null &&
        composed.sourceHeight != null &&
        composed.sourceWidth! > 1 &&
        composed.sourceHeight! > 1) {
      return Size(composed.sourceWidth!, composed.sourceHeight!);
    }
    if (composed.width >= composed.height) {
      return Size(longPts, longPts * composed.height / composed.width);
    }
    return Size(longPts * composed.width / composed.height, longPts);
  }

  /// Whether [_addEditedPage] draws [a] as a vector, so the marks bitmap does
  /// not need it. Mirrors what [_paintMarks] skips.
  bool _exportsAsVector(EditorAnnotation a, PdfUnicodeFonts uni) {
    if (a is ShapeAnnotation) {
      return !a.burnsBlackCover && (a.type == ShapeType.rect || a.type == ShapeType.whiteout);
    }
    if (a is TextAnnotation) return _canVectorize(a, uni);
    return false;
  }

  /// One output page: [image] (the page bitmap, or only the marks; null when
  /// every mark is a vector) with the rectangle shapes and searchable text
  /// added as vectors on top.
  void _addEditedPage(
    pw.Document pdf, {
    required double pageW,
    required double pageH,
    required pw.MemoryImage? image,
    required PageLayer? layer,
    required EditorPdfFonts fonts,
    required PdfUnicodeFonts uni,
    bool drawEraseCovers = true,
  }) {
    const rtlDetect = RtlDetectionService();
    final shapes = (layer?.shapes ?? const <ShapeAnnotation>[])
        .where((s) =>
            s.visible &&
            !s.burnsBlackCover &&
            (s.type == ShapeType.rect || s.type == ShapeType.whiteout) &&
            (drawEraseCovers || s.metadata[eraseTextKey] != true))
        .toList();
    final texts = (layer?.texts ?? const <TextAnnotation>[])
        .where((t) => t.visible && t.text.isNotEmpty && _canVectorize(t, uni))
        .toList();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageW, pageH, marginAll: 0),
        build: (_) => pw.SizedBox(
          width: pageW,
          height: pageH,
          child: pw.Stack(
            children: [
              if (image != null)
                pw.SizedBox(
                  width: pageW,
                  height: pageH,
                  child: pw.Image(image, fit: pw.BoxFit.fill),
                ),
              for (final s in shapes) _buildPdfShape(s, pageW, pageH),
              for (final t in texts) _buildPdfText(t, pageW, pageH, fonts, uni, rtlDetect),
            ],
          ),
        ),
      ),
    );
  }

  /// The vector text widget [renderToPdfFile] places for [t].
  @visibleForTesting
  pw.Widget buildPdfTextForTest(TextAnnotation t, double pageW, double pageH, PdfUnicodeFonts uni) =>
      _buildPdfText(t, pageW, pageH, EditorPdfFonts(), uni, const RtlDetectionService());

  /// The page image [renderToPdfFile] would embed for [index], without the
  /// vector text it adds on top. Used by the golden tests.
  @visibleForTesting
  Future<Uint8List?> composePageImageForTest({
    required int index,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    int quarterTurns = 0,
  }) async {
    final uni = PdfUnicodeFonts();
    await uni.load();
    final composed = await _composePagePng(
      index: index,
      doc: null,
      pageCache: pageCache,
      layers: layers,
      uni: uni,
      quarterTurns: quarterTurns,
      sourcePage: index,
    );
    return composed?.bytes;
  }

  Future<Uint8List> _blankPagePng() async {
    const width = 612.0;
    const height = 792.0;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final image = await recorder.endRecording().toImage(width.toInt(), height.toInt());
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List() ?? Uint8List(0);
    } finally {
      image.dispose();
    }
  }

  /// Whether [t] can be exported as real (searchable) vector text.
  /// Rotated and multi-run text stay in the page image so they match preview.
  bool _canVectorize(TextAnnotation t, PdfUnicodeFonts uni) {
    return textExportsAsSearchableVector(
      runCount: t.runs?.length ?? 0,
      rotation: t.rotation,
      latin1: _isLatin1(t.text),
      unicodeFontAvailable: uni.pick(t) != null,
    );
  }

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
    // Same box as RtlTextRenderer and the on-screen Text: anchored at pos,
    // as wide as the text until it wraps at the page edge. A fixed-width box
    // would push a one-line RTL label to the right margin.
    return pw.Positioned(
      left: t.pos.dx * pageW,
      top: t.pos.dy * pageH,
      child: pw.ConstrainedBox(
        constraints: pw.BoxConstraints(maxWidth: (pageW * (1 - t.pos.dx)).clamp(1.0, pageW)),
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
  /// the export matches the on-screen preview). Returns false when the image
  /// cannot be decoded, so the caller can stop instead of dropping it.
  Future<bool> _drawImageAnnotation(Canvas canvas, Size size, ImageAnnotation ann) async {
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
      return true;
    } catch (_) {
      return false;
    }
  }

  void _paintNote(Canvas canvas, Size size, StickyNoteAnnotation note) {
    if (!note.visible || note.text.isEmpty) return;
    final rect = Rect.fromLTWH(
      note.pos.dx * size.width,
      note.pos.dy * size.height,
      size.width * 0.22,
      size.height * 0.12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = note.color.value,
    );
    final rtl = const RtlDetectionService().isRtl(note.text);
    final painter = TextPainter(
      text: TextSpan(
        text: note.text,
        style: TextStyle(color: Colors.black87, fontSize: size.height * 0.018, height: 1.25),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
      maxLines: 6,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 8);
    painter.paint(canvas, rect.topLeft + const Offset(4, 4));
  }

  /// Page bitmap with the marks painted on it. With [marksOnlySize] there is
  /// no page bitmap: the marks are painted on a transparent canvas of that
  /// pixel size, for the overlay of a source-preserving export.
  Future<_ComposedPage?> _composePagePng({
    required int index,
    required pdfx.PdfDocument? doc,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    required PdfUnicodeFonts uni,
    int quarterTurns = 0,
    int? sourcePage,
    Size? marksOnlySize,
  }) async {
    if (marksOnlySize != null) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder); // nothing drawn: a transparent canvas
      final blank = await recorder
          .endRecording()
          .toImage(marksOnlySize.width.toInt(), marksOnlySize.height.toInt());
      return _paintMarks(index: index, base: blank, layers: layers, uni: uni);
    }
    Uint8List? baseBytes;
    double? sourceWidth;
    double? sourceHeight;
    final pdfPage = sourcePage ?? index;
    if (pdfPage < 0) {
      baseBytes = pageCache[index] ?? await _blankPagePng();
      sourceWidth = 612;
      sourceHeight = 792;
    } else if (doc != null) {
      final page = await doc.getPage(pdfPage + 1);
      try {
        sourceWidth = page.width;
        sourceHeight = page.height;
        final planned = planPageRenderSize(
          pageWidth: page.width,
          pageHeight: page.height,
          renderMaxEdge: exportMaxEdge,
        );
        final img = await page.render(
          width: planned.width,
          height: planned.height,
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
    if (baseBytes == null || baseBytes.isEmpty) return null;
    var pageBytes = baseBytes;
    const rotator = EditorPageTransformService();
    for (var turn = 0; turn < quarterTurns; turn++) {
      final rotated = await rotator.rotateClockwise(pageBytes);
      if (rotated == null) {
        throw ExportPageException(index, 'the page rotation could not be applied');
      }
      pageBytes = rotated;
    }

    if (quarterTurns.isOdd && sourceWidth != null && sourceHeight != null) {
      final swap = sourceWidth;
      sourceWidth = sourceHeight;
      sourceHeight = swap;
    }

    final codec = await ui.instantiateImageCodec(pageBytes);
    final frame = await codec.getNextFrame();
    return _paintMarks(
      index: index,
      base: frame.image,
      layers: layers,
      uni: uni,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  /// Paint the layer of [index] over [base] and encode a PNG. Disposes [base].
  Future<_ComposedPage?> _paintMarks({
    required int index,
    required ui.Image base,
    required Map<int, PageLayer> layers,
    required PdfUnicodeFonts uni,
    double? sourceWidth,
    double? sourceHeight,
  }) async {
    try {
      final size = Size(base.width.toDouble(), base.height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawImage(base, Offset.zero, Paint());
      final layer = layers[index];
      if (layer != null) {
        // Background layer: images (photos / logos / scanned signatures).
        for (final im in layer.images) {
          if (!im.visible) continue;
          if (!await _drawImageAnnotation(canvas, size, im)) {
            throw ExportPageException(index, 'an inserted image could not be decoded');
          }
        }
        for (final m in layer.markups) {
          if (!m.visible) continue;
          AnnotationDraw.markup(canvas, size, m);
        }
        for (final s in layer.strokes) {
          if (!s.visible) continue;
          final ink = s.color.withOpacity((s.color.opacity * s.opacity).clamp(0.0, 1.0));
          AnnotationDraw.stroke(canvas, size, s.points, ink, s.width);
        }
        for (final s in layer.shapes) {
          if (!s.visible) continue;
          if (s.burnsBlackCover) {
            // Burn the cover into the bitmap. A separate PDF object could be
            // deleted and would reveal the page underneath.
            AnnotationDraw.secureCover(canvas, size, s.start, s.end);
            continue;
          }
          if (s.type == ShapeType.rect || s.type == ShapeType.whiteout) {
            continue;
          }
          AnnotationDraw.shape(canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
        }
        // Stamps (bordered label boxes) sit above shapes, matching the preview.
        for (final st in layer.stamps) {
          if (!st.visible) continue;
          _stampRenderer.paint(canvas, size, st);
        }
        for (final note in layer.notes) {
          _paintNote(canvas, size, note);
        }
        // Text that can't be exported as vector (non-Latin without a bundled
        // Unicode font, or multi-run rich text) is rasterized with full
        // RTL/BiDi handling so it still exports in the correct visual order.
        for (final t in layer.texts) {
          if (!t.visible) continue;
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
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
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

typedef _ComposedPage = ({
  Uint8List bytes,
  int width,
  int height,
  double? sourceWidth,
  double? sourceHeight,
});
