import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/editor_page_render_service.dart';
import 'package:ai_pdf/features/editor/data/page_cache_policy.dart';

void main() {
  group('PageCachePolicy', () {
    test('legacy cache hit skips regardless of size', () {
      expect(
        PageCachePolicy.shouldSkip(
          hasBytes: true,
          cachedEdge: null,
          requestedEdge: 2400,
          tracksResolution: false,
        ),
        isTrue,
      );
    });

    test('a low-res placeholder does not block the sharp render', () {
      expect(
        PageCachePolicy.shouldSkip(
          hasBytes: true,
          cachedEdge: 1280,
          requestedEdge: 2400,
          tracksResolution: true,
        ),
        isFalse,
      );
    });

    test('an equal or sharper cache hit is reused', () {
      expect(
        PageCachePolicy.shouldSkip(
          hasBytes: true,
          cachedEdge: 2400,
          requestedEdge: 1280,
          tracksResolution: true,
        ),
        isTrue,
      );
    });

    test('a late low-res frame does not replace a sharp one', () {
      expect(
        PageCachePolicy.shouldStore(cachedEdge: 2400, renderedEdge: 1280),
        isFalse,
      );
      expect(
        PageCachePolicy.shouldStore(cachedEdge: 1280, renderedEdge: 2400),
        isTrue,
      );
    });
  });

  test('an A4 page is rendered at the requested long edge, not at 72dpi points', () {
    final planned = planPageRenderSize(
      pageWidth: 595.28,
      pageHeight: 841.89,
      renderMaxEdge: 2400,
    );
    expect(planned.edge, 2400);
    expect(planned.height, closeTo(2400, 0.01));
    expect(planned.width / planned.height, closeTo(595.28 / 841.89, 0.0001));
  });

  test('a page larger than the cap is still limited to the cap', () {
    final planned = planPageRenderSize(
      pageWidth: 3000,
      pageHeight: 2000,
      renderMaxEdge: 2400,
    );
    expect(planned.edge, 2400);
    expect(planned.width, closeTo(2400, 0.01));
  });

  test('render flight keys include the cache so two maps do not share one future', () {
    expect(
      renderFlightKey(docId: 7, cacheId: 1, pageIndex: 0, edge: 2400),
      isNot(renderFlightKey(docId: 7, cacheId: 2, pageIndex: 0, edge: 2400)),
    );
  });

  test('one cancelled caller does not clear a gate that another caller still wants', () {
    final gates = RenderRequestGates();
    var first = true;
    var second = true;
    bool gateA() => first;
    bool gateB() => second;
    gates.add(gateA);
    gates.add(gateB);
    first = false;
    expect(gates.anyStillCurrent, isTrue);
    second = false;
    expect(gates.anyStillCurrent, isFalse);
  });
}
