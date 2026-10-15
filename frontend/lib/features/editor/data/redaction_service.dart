import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:ai_pdf/core/config/app_settings.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// A rectangular region marked for redaction (Phase 17 + E1.7).
class RedactionRegion {
  final Rect rect;
  final String? label;
  final int pageIndex;

  const RedactionRegion(this.rect, {this.label, this.pageIndex = 0});
}

class SecureRedactionOutcome {
  /// True only when the PDF bytes no longer contain the targeted content.
  /// This build never sets it: the libraries cannot delete existing operators.
  final bool contentRemoved;
  final String reason;

  const SecureRedactionOutcome({
    required this.contentRemoved,
    required this.reason,
  });

  bool get accepted => contentRemoved;
}

class RedactionResult {
  final List<PdfTextElement> remainingText;
  final List<int> removedIndices;
  final List<Rect> coverRects;

  const RedactionResult({
    required this.remainingText,
    required this.removedIndices,
    required this.coverRects,
  });

  int get removedCount => removedIndices.length;
}

/// In-memory preview of which text boxes a redaction rectangle covers.
///
/// [apply] only filters a Dart list used for search and hit-testing. It does
/// not open a PDF, does not edit a content stream, and is not secure
/// redaction. The on-canvas tool paints a black rectangle. Deleting that
/// rectangle, or reading the original file, still reveals the text.
///
/// [redactViaBackend] can ask the server to run PyMuPDF `apply_redactions`,
/// which does remove content, but that uploads the document and nothing in
/// the editor calls it. Do not describe the black cover as secure.
class RedactionService {
  const RedactionService();

  static const double coverageThreshold = 0.15;

  RedactionResult apply(List<PdfTextElement> elements, List<RedactionRegion> regions) {
    final remaining = <PdfTextElement>[];
    final removed = <int>[];
    for (var i = 0; i < elements.length; i++) {
      if (_isCovered(elements[i].rect, regions)) {
        removed.add(i);
      } else {
        remaining.add(elements[i]);
      }
    }
    return RedactionResult(
      remainingText: remaining,
      removedIndices: removed,
      coverRects: mergeOverlapping([for (final r in regions) r.rect]),
    );
  }

  List<int> coveredElements(List<PdfTextElement> elements, List<RedactionRegion> regions) {
    final out = <int>[];
    for (var i = 0; i < elements.length; i++) {
      if (_isCovered(elements[i].rect, regions)) out.add(i);
    }
    return out;
  }

  List<Rect> mergeOverlapping(List<Rect> rects) {
    final result = <Rect>[for (final r in rects) r];
    var merged = true;
    while (merged) {
      merged = false;
      outer:
      for (var i = 0; i < result.length; i++) {
        for (var j = i + 1; j < result.length; j++) {
          if (_overlapsOrTouches(result[i], result[j])) {
            final union = result[i].expandToInclude(result[j]);
            result.removeAt(j);
            result[i] = union;
            merged = true;
            break outer;
          }
        }
      }
    }
    return result;
  }

  bool _isCovered(Rect element, List<RedactionRegion> regions) {
    if (element.width <= 0 || element.height <= 0) {
      for (final region in regions) {
        if (region.rect.contains(element.topLeft)) return true;
      }
      return false;
    }
    final area = element.width * element.height;
    for (final region in regions) {
      final inter = element.intersect(region.rect);
      if (inter.width <= 0 || inter.height <= 0) continue;
      final coveredFraction = (inter.width * inter.height) / area;
      if (coveredFraction >= coverageThreshold) return true;
    }
    return false;
  }

  bool _overlapsOrTouches(Rect a, Rect b) {
    return a.left <= b.right && b.left <= a.right && a.top <= b.bottom && b.top <= a.bottom;
  }

  /// Fail closed. `pdf` 3.11 and `pdfx` 2.9 cannot delete existing content
  /// streams, images under a rectangle, or document metadata.
  ///
  /// [pdfBytes] is not modified. A secret that is still present is reported
  /// in [SecureRedactionOutcome.reason]. Absence of the ASCII secret is still
  /// not success, because a compressed or encoded copy would not be visible
  /// to this check.
  SecureRedactionOutcome secureRedact({
    required List<RedactionRegion> regions,
    List<int>? pdfBytes,
    String? secret,
  }) {
    if (regions.isEmpty) {
      return const SecureRedactionOutcome(
        contentRemoved: false,
        reason: 'Refused. No redaction region.',
      );
    }
    final stillThere = pdfBytes != null &&
        secret != null &&
        secret.isNotEmpty &&
        bytesContainAscii(pdfBytes, secret);
    final reason = stillThere
        ? 'Refused. "$secret" is still in the PDF bytes. pdf 3.11 and pdfx 2.9 cannot delete existing content.'
        : 'Refused. This build cannot prove content removal, so the file is not marked redacted.';
    return SecureRedactionOutcome(contentRemoved: false, reason: reason);
  }

  /// ASCII search only. Used to show that a refused redaction left the bytes
  /// untouched. Not a PDF text extractor.
  static bool bytesContainAscii(List<int> pdfBytes, String secret) {
    if (secret.isEmpty) return false;
    final needle = secret.codeUnits;
    if (needle.any((unit) => unit > 127)) return false;
    if (needle.length > pdfBytes.length) return false;
    for (var i = 0; i <= pdfBytes.length - needle.length; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (pdfBytes[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  /// True redaction via backend — E1.7 Phase 6
  /// Calls POST /document-ai/redact with file + areas_json, returns redacted PDF path
  Future<String?> redactViaBackend({
    required String filePath,
    required List<RedactionRegion> regions,
    String? teamId,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final areas = regions.map((r) => {
        'page': r.pageIndex,
        'x0': r.rect.left.clamp(0.0, 1.0),
        'y0': r.rect.top.clamp(0.0, 1.0),
        'x1': r.rect.right.clamp(0.0, 1.0),
        'y1': r.rect.bottom.clamp(0.0, 1.0),
        'fill': 'white',
      }).toList();

      final jsonStr = jsonEncode(areas);

      final dio = Dio(BaseOptions(
        baseUrl: AppSettings.instance.apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ));

      final headers = <String, String>{};
      if (teamId != null) headers['X-Team-Id'] = teamId;

      final resp = await dio.post(
        '/document-ai/redact',
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(filePath),
          'areas_json': jsonStr,
        }),
        options: Options(headers: headers, responseType: ResponseType.bytes),
      );

      if (resp.statusCode == 200) {
        final bytes = resp.data is Uint8List ? resp.data as Uint8List : Uint8List.fromList(resp.data as List<int>);
        final dir = await getTemporaryDirectory();
        final outPath = '${dir.path}/redacted_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final outFile = File(outPath);
        await outFile.writeAsBytes(bytes);
        return outPath;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[RedactionService] backend redact failed: $e');
    }
    return null;
  }
}
