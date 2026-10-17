import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Rect;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/editor_export_service.dart';
import 'package:ai_pdf/features/editor/data/editor_page_render_service.dart';
import 'package:ai_pdf/features/editor/data/redaction_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Answers every request with one canned response and records the request.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, this.body, {this.headers = const {}, this.fail});

  final int status;
  final List<int> body;
  final Map<String, List<String>> headers;
  final DioExceptionType? fail;
  RequestOptions? last;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    last = options;
    if (fail != null) {
      throw DioException(requestOptions: options, type: fail!);
    }
    return ResponseBody.fromBytes(body, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

final _pdfBody = utf8.encode('%PDF-1.7\n${'x' * 200}\n%%EOF');
const _allChecks = 'page_count,text_extraction,annotations,links,form_fields,rendered_fill';

void main() {
  late Directory tmp;
  late String source;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('redact_test');
    source = '${tmp.path}/in.pdf';
    File(source).writeAsBytesSync(_pdfBody);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<BackendRedactionResult> run(
    _FakeAdapter adapter, {
    List<RedactionRegion>? regions,
    String? path,
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'))..httpClientAdapter = adapter;
    return const RedactionService().redactViaBackend(
      filePath: path ?? source,
      regions: regions ?? const [RedactionRegion(Rect.fromLTRB(0.1, 0.1, 0.4, 0.2), pageIndex: 0)],
      dio: dio,
      outputDirectory: () async => tmp,
    );
  }

  group('redactViaBackend', () {
    test('accepts a PDF only when the server lists every check', () async {
      final adapter = _FakeAdapter(200, _pdfBody, headers: {
        'content-type': ['application/pdf'],
        'x-redaction-verified': [_allChecks],
      });
      final result = await run(adapter);
      expect(result.ok, isTrue, reason: result.error);
      expect(File(result.path!).readAsBytesSync(), _pdfBody);
      expect(result.checks, containsAll(RedactionService.requiredServerChecks));
      final form = adapter.last!.data as FormData;
      final areas = jsonDecode(form.fields.firstWhere((f) => f.key == 'areas_json').value) as List;
      expect(areas.single, {'page': 0, 'x0': 0.1, 'y0': 0.1, 'x1': 0.4, 'y1': 0.2, 'fill': 'black'});
      // The real file name never leaves the device.
      expect(form.files.single.value.filename, 'document.pdf');
    });

    test('a 200 without the verification header is a failure', () async {
      final result = await run(_FakeAdapter(200, _pdfBody, headers: {
        'x-redaction-verified': ['page_count,text_extraction'],
      }));
      expect(result.ok, isFalse);
      expect(tmp.listSync().whereType<File>().where((f) => f.path.contains('redacted_')), isEmpty);
    });

    test('a 200 that is not a PDF is a failure', () async {
      final result = await run(_FakeAdapter(200, utf8.encode('<html>${'x' * 100}</html>'), headers: {
        'x-redaction-verified': [_allChecks],
      }));
      expect(result.ok, isFalse);
      expect(result.error, contains('did not return a PDF'));
    });

    test('a refusal shows the server reason', () async {
      final result = await run(_FakeAdapter(
        422,
        utf8.encode(jsonEncode({'detail': 'Area 0 page 3 is outside the document (1 pages). No page was redacted.'})),
        headers: {'content-type': ['application/json']},
      ));
      expect(result.ok, isFalse);
      expect(result.error, contains('outside the document'));
    });

    test('a network error is a failure, not a cover', () async {
      final result = await run(_FakeAdapter(0, const [], fail: DioExceptionType.connectionError));
      expect(result.ok, isFalse);
      expect(result.error, contains('could not be reached'));
    });

    test('invalid regions are refused before anything is uploaded', () async {
      final adapter = _FakeAdapter(200, _pdfBody, headers: {'x-redaction-verified': [_allChecks]});
      for (final bad in [
        const RedactionRegion(Rect.fromLTRB(0.1, 0.1, 0.1, 0.2)),
        const RedactionRegion(Rect.fromLTRB(-0.1, 0.1, 0.4, 0.2)),
        const RedactionRegion(Rect.fromLTRB(0.1, 0.1, double.nan, 0.2)),
        const RedactionRegion(Rect.fromLTRB(0.1, 0.1, 0.4, 0.2), pageIndex: -1),
      ]) {
        final result = await run(adapter, regions: [bad]);
        expect(result.ok, isFalse);
      }
      expect((await run(adapter, regions: const [])).ok, isFalse);
      expect(adapter.calls, 0);
    });

    test('a missing source file is reported', () async {
      final adapter = _FakeAdapter(200, _pdfBody, headers: {'x-redaction-verified': [_allChecks]});
      final result = await run(adapter, path: '${tmp.path}/gone.pdf');
      expect(result.ok, isFalse);
      expect(adapter.calls, 0);
    });
  });

  group('toSourcePageRect', () {
    const rect = Rect.fromLTRB(0.1, 0.2, 0.3, 0.6);

    Offset turnClockwise(Offset p) => Offset(1 - p.dy, p.dx);

    test('no turn keeps the rectangle', () {
      expect(RedactionService.toSourcePageRect(rect), rect);
    });

    for (final turns in [1, 2, 3, 5]) {
      test('$turns clockwise turns map back to the source page', () {
        final mapped = RedactionService.toSourcePageRect(rect, quarterTurns: turns)!;
        // Turning the mapped source corners forward must land on the drawn box.
        var a = mapped.topLeft;
        var b = mapped.bottomRight;
        for (var i = 0; i < turns % 4; i++) {
          a = turnClockwise(a);
          b = turnClockwise(b);
        }
        final shown = Rect.fromPoints(a, b);
        expect(shown.left, closeTo(rect.left, 1e-9));
        expect(shown.top, closeTo(rect.top, 1e-9));
        expect(shown.right, closeTo(rect.right, 1e-9));
        expect(shown.bottom, closeTo(rect.bottom, 1e-9));
      });
    }

    test('non-finite or empty rectangles are rejected, overhang is cut', () {
      expect(RedactionService.toSourcePageRect(const Rect.fromLTRB(0.1, 0.1, double.infinity, 0.2)), isNull);
      expect(RedactionService.toSourcePageRect(const Rect.fromLTRB(1.1, 0.1, 1.4, 0.2)), isNull);
      expect(
        RedactionService.toSourcePageRect(const Rect.fromLTRB(-0.2, 0.1, 0.4, 1.3)),
        const Rect.fromLTRB(0, 0.1, 0.4, 1),
      );
    });
  });

  group('annotation flags', () {
    test('a server-redacted box is burned like a cover', () {
      final box = ShapeAnnotation(ShapeType.rect, Offset.zero, const Offset(0.2, 0.2), const Color(0xFF000000), 1, true)
        ..metadata[serverRedactedKey] = true;
      expect(box.isServerRedacted, isTrue);
      expect(box.burnsBlackCover, isTrue);
      expect(box.isSecureRedaction, isFalse);
    });
  });

  group('export', () {
    testWidgets('a page that cannot be produced stops the export', (tester) async {
      await tester.runAsync(() async {
        Object? error;
        try {
          await const EditorExportService().renderToPdfFile(
            doc: null,
            pageCache: const {},
            layers: <int, PageLayer>{},
            pageCount: 2,
          );
        } catch (e) {
          error = e;
        }
        expect(error, isA<ExportPageException>());
        expect((error! as ExportPageException).pageIndex, 0);
        expect(error.toString(), 'Page 1: the page could not be rendered');
      });
    });
  });

  test('render flights differ by source page and rotation', () {
    final a = renderFlightKey(docId: 1, cacheId: 2, pageIndex: 3, edge: 100);
    expect(a, renderFlightKey(docId: 1, cacheId: 2, pageIndex: 3, edge: 100, sourcePage: 3));
    expect(a, isNot(renderFlightKey(docId: 1, cacheId: 2, pageIndex: 3, edge: 100, sourcePage: 4)));
    expect(a, isNot(renderFlightKey(docId: 1, cacheId: 2, pageIndex: 3, edge: 100, quarterTurns: 1)));
  });
}
