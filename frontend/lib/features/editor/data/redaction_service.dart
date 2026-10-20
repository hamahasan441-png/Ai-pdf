import 'dart:io';
import 'dart:ui' show Rect;
import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:ai_pdf/core/config/app_settings.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
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
  /// [RedactionService.secureRedact] (on-device) never sets it: the Dart
  /// libraries cannot delete existing operators. Server redaction reports
  /// through [BackendRedactionResult] instead.
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
/// [redactViaBackend] asks the server to run PyMuPDF `apply_redactions` and
/// re-check the output. That does remove content, but it uploads the
/// document, so the editor calls it only after the user agrees for that one
/// redaction. Do not describe the black cover as secure.
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

  /// On-device secure redaction. Fails closed: `pdf` 3.11 and `pdfx` 2.9
  /// cannot delete existing content streams, images under a rectangle, or
  /// document metadata. Use [redactViaBackend] with the user's consent.
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

  /// Checks the server must report in `X-Redaction-Verified` before a
  /// redacted file is accepted. See backend secure_redact.verify_redaction.
  static const requiredServerChecks = [
    'page_count',
    'text_extraction',
    'annotations',
    'links',
    'form_fields',
    'rendered_fill',
    'hidden_copies',
  ];

  /// Map a rectangle drawn on the editor page back to the source page.
  ///
  /// [rect] is normalized (0..1) on the page as shown, after the user turned
  /// it [quarterTurns] times clockwise in this session. The result is
  /// normalized on the source page as a PDF viewer shows it (its own /Rotate
  /// applied), which is the space the server expects. Returns null for a
  /// non-finite or empty rectangle. A rectangle that runs past the page edge
  /// is cut at the edge.
  static Rect? toSourcePageRect(Rect rect, {int quarterTurns = 0}) {
    final values = [rect.left, rect.top, rect.right, rect.bottom];
    if (values.any((v) => !v.isFinite)) return null;
    var r = Rect.fromLTRB(
      rect.left.clamp(0.0, 1.0),
      rect.top.clamp(0.0, 1.0),
      rect.right.clamp(0.0, 1.0),
      rect.bottom.clamp(0.0, 1.0),
    );
    final turns = quarterTurns % 4;
    for (var i = 0; i < turns; i++) {
      // One clockwise turn maps source (u, v) to shown (1 - v, u), so shown
      // (x, y) came from source (y, 1 - x).
      r = Rect.fromLTRB(r.top, 1 - r.right, r.bottom, 1 - r.left);
    }
    if (r.width <= 0 || r.height <= 0) return null;
    return r;
  }

  /// Secure redaction on the server: PyMuPDF `apply_redactions`, then an
  /// independent reopen of the output. Uploads the whole file, so the caller
  /// must have the user's consent for this one request.
  ///
  /// [regions] use source page indexes and [toSourcePageRect] coordinates.
  /// The returned file is accepted only when the response is a PDF and the
  /// server lists every check in [requiredServerChecks]. Any other outcome
  /// is an error; there is no partial success and no fallback cover.
  Future<BackendRedactionResult> redactViaBackend({
    required String filePath,
    required List<RedactionRegion> regions,
    String? teamId,
    Dio? dio,
    Future<Directory> Function()? outputDirectory,
  }) async {
    if (regions.isEmpty) {
      return const BackendRedactionResult.failure('No redaction region.', RedactionFailure.invalidArea);
    }
    final areas = <Map<String, Object>>[];
    for (final r in regions) {
      final rect = r.rect;
      final values = [rect.left, rect.top, rect.right, rect.bottom];
      if (r.pageIndex < 0 ||
          values.any((v) => !v.isFinite || v < 0 || v > 1) ||
          rect.width <= 0 ||
          rect.height <= 0) {
        return const BackendRedactionResult.failure('A redaction region is outside the page.', RedactionFailure.invalidArea);
      }
      areas.add({
        'page': r.pageIndex,
        'x0': rect.left,
        'y0': rect.top,
        'x1': rect.right,
        'y1': rect.bottom,
        'fill': 'black',
      });
    }

    final file = File(filePath);
    if (!await file.exists()) {
      return const BackendRedactionResult.failure('The source PDF is no longer on this device.', RedactionFailure.missingFile);
    }

    final client = dio ??
        Dio(BaseOptions(
          baseUrl: AppSettings.instance.apiBaseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ));
    final headers = <String, String>{};
    if (teamId != null) headers['X-Team-Id'] = teamId;

    final Response<List<int>> resp;
    try {
      resp = await client.post<List<int>>(
        '/document-ai/redact',
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(filePath, filename: 'document.pdf'),
          'areas_json': jsonEncode(areas),
        }),
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      return BackendRedactionResult.failure(_networkMessage(e), _networkFailure(e));
    } catch (_) {
      return const BackendRedactionResult.failure('The redaction server could not be reached.', RedactionFailure.network);
    }

    final status = resp.statusCode ?? 0;
    final body = resp.data ?? const <int>[];
    if (status != 200) {
      return BackendRedactionResult.failure(_serverMessage(status, body), _serverFailure(status), detail: _serverDetail(body));
    }
    if (!_looksLikePdf(body)) {
      return const BackendRedactionResult.failure('The server did not return a PDF. Nothing was redacted.', RedactionFailure.badResponse);
    }
    // Structural validation before the file is trusted. A magic check alone
    // would accept a truncated or corrupt response; parsing proves the
    // object tree, xref and page tree are intact, and that at least one page
    // survived. Failure here means the output is NOT adopted as redacted.
    try {
      final parsed = PdfObjectStore.parse(Uint8List.fromList(body));
      if (parsed.pages.isEmpty) {
        return const BackendRedactionResult.failure(
          'The redacted PDF has no pages. The file was not used.',
          RedactionFailure.badResponse,
        );
      }
    } catch (_) {
      return const BackendRedactionResult.failure(
        'The redacted PDF failed validation. The file was not used.',
        RedactionFailure.badResponse,
      );
    }
    final verified = (resp.headers.value('x-redaction-verified') ?? '')
        .split(',')
        .map((s) => s.trim())
        .toSet();
    final missing = requiredServerChecks.where((c) => !verified.contains(c)).toList();
    if (missing.isNotEmpty) {
      return const BackendRedactionResult.failure(
        'The server did not confirm the content was removed. The file was not used.',
        RedactionFailure.unverified,
      );
    }

    try {
      final dir = await (outputDirectory ?? getTemporaryDirectory)();
      final outPath = '${dir.path}/redacted_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final partial = File('$outPath.partial');
      await partial.writeAsBytes(body, flush: true);
      await partial.rename(outPath);
      final elsewhere = int.tryParse(resp.headers.value('x-redaction-occurrences-elsewhere') ?? '') ?? 0;
      return BackendRedactionResult.success(
        outPath,
        verified.toList()..sort(),
        occurrencesElsewhere: elsewhere < 0 ? 0 : elsewhere,
      );
    } catch (_) {
      return const BackendRedactionResult.failure('The redacted PDF could not be saved on this device.', RedactionFailure.saveFailed);
    }
  }

  static bool _looksLikePdf(List<int> body) {
    const magic = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
    if (body.length < 64) return false;
    final head = body.length < 1024 ? body.length : 1024;
    for (var i = 0; i + magic.length <= head; i++) {
      var match = true;
      for (var j = 0; j < magic.length; j++) {
        if (body[i + j] != magic[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  static String _serverMessage(int status, List<int> body) {
    final detail = _serverDetail(body);
    if (status == 401 || status == 403) {
      return 'The server did not accept this request. Sign in again and retry. Nothing was redacted.';
    }
    if (status == 415) return 'The file is not a PDF. Nothing was redacted.';
    if (status == 429) return detail ?? 'Daily limit reached.';
    if (status == 413) return 'The PDF is too large for the redaction server.';
    if (detail != null) return 'Redaction refused: $detail';
    return 'Redaction failed on the server (HTTP $status). Nothing was redacted.';
  }

  static RedactionFailure _serverFailure(int status) => switch (status) {
        401 || 403 => RedactionFailure.auth,
        413 => RedactionFailure.tooLarge,
        415 => RedactionFailure.notPdf,
        422 => RedactionFailure.refused,
        429 => RedactionFailure.limit,
        _ => RedactionFailure.server,
      };

  /// The server's short reason (never document text), for a 422.
  static String? _serverDetail(List<int> body) {
    try {
      final decoded = jsonDecode(utf8.decode(body, allowMalformed: true));
      final d = decoded is Map ? decoded['detail'] : null;
      return d is String && d.length <= 200 ? d : null;
    } catch (_) {
      return null;
    }
  }

  static RedactionFailure _networkFailure(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          RedactionFailure.timeout,
        _ => RedactionFailure.network,
      };

  static String _networkMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The redaction server timed out. Nothing was redacted.';
      default:
        return 'The redaction server could not be reached. Nothing was redacted.';
    }
  }
}

/// Why a secure redaction did not happen. The screen shows a translated
/// message for each; [BackendRedactionResult.error] keeps English text for
/// logs and tests.
enum RedactionFailure {
  invalidArea,
  missingFile,
  network,
  timeout,
  auth,
  notPdf,
  tooLarge,
  limit,
  refused,
  server,
  badResponse,
  unverified,
  saveFailed,
}

/// Outcome of [RedactionService.redactViaBackend]. [path] is set only when
/// the server returned a PDF and confirmed every required check.
class BackendRedactionResult {
  final String? path;
  final String? error;
  final List<String> checks;

  /// Visible copies of the redacted text elsewhere in the document that the
  /// user did not select. The server counts them and leaves them as they are.
  final int occurrencesElsewhere;

  final RedactionFailure? failure;

  /// Server-provided reason for a refused request.
  final String? detail;

  const BackendRedactionResult.success(
    String this.path,
    this.checks, {
    this.occurrencesElsewhere = 0,
  })  : error = null,
        failure = null,
        detail = null;

  const BackendRedactionResult.failure(
    String this.error,
    RedactionFailure this.failure, {
    this.detail,
  })  : path = null,
        checks = const [],
        occurrencesElsewhere = 0;

  bool get ok => path != null;
}
