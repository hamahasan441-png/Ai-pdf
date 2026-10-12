import 'package:flutter_test/flutter_test.dart';

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
}
