import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/page_reorder_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

void main() {
  const svc = PageReorderService();

  group('PageReorderService (Phase 10)', () {
    test('movePage swaps pages and their layers', () {
      final cache = <int, Uint8List>{
        0: Uint8List.fromList([0]),
        1: Uint8List.fromList([1]),
        2: Uint8List.fromList([2]),
      };
      final layers = <int, PageLayer>{
        0: PageLayer(),
        1: PageLayer(),
        2: PageLayer(),
      };
      svc.movePage(
        fromIndex: 0,
        toIndex: 2,
        pageCache: cache,
        layers: layers,
        pageCount: 3,
      );
      expect(cache[0]![0], 1); // old page 1 is now at index 0
      expect(cache[2]![0], 0); // old page 0 moved to index 2
    });

    test('deletePage removes a page and shifts the rest', () {
      final cache = <int, Uint8List>{
        0: Uint8List.fromList([0]),
        1: Uint8List.fromList([1]),
        2: Uint8List.fromList([2]),
      };
      final layers = <int, PageLayer>{};
      final newCount = svc.deletePage(
        index: 1,
        pageCache: cache,
        layers: layers,
        pageCount: 3,
      );
      expect(newCount, 2);
      expect(cache[0]![0], 0);
      expect(cache[1]![0], 2);
    });

    test('deletePage refuses to delete the last page', () {
      final cache = <int, Uint8List>{0: Uint8List.fromList([0])};
      final layers = <int, PageLayer>{};
      final newCount = svc.deletePage(
        index: 0,
        pageCache: cache,
        layers: layers,
        pageCount: 1,
      );
      expect(newCount, 1);
      expect(cache, isNotEmpty);
    });

    test('duplicatePage inserts a copy after the source', () {
      final cache = <int, Uint8List>{
        0: Uint8List.fromList([10]),
        1: Uint8List.fromList([20]),
      };
      final layers = <int, PageLayer>{};
      final newCount = svc.duplicatePage(
        index: 0,
        pageCache: cache,
        layers: layers,
        pageCount: 2,
      );
      expect(newCount, 3);
      expect(cache[0]![0], 10);
      expect(cache[1]![0], 10); // duplicate of page 0
      expect(cache[2]![0], 20); // old page 1 shifted
    });

    test('insertBlankPage shifts pages and adds an empty layer', () {
      final cache = <int, Uint8List>{
        0: Uint8List.fromList([0]),
        1: Uint8List.fromList([1]),
      };
      final layers = <int, PageLayer>{};
      final newCount = svc.insertBlankPage(
        index: 1,
        pageCache: cache,
        layers: layers,
        pageCount: 2,
      );
      expect(newCount, 3);
      expect(cache.containsKey(1), isFalse); // blank page has no cache
      expect(cache[2]![0], 1); // old page 1 shifted to 2
      expect(layers.containsKey(1), isTrue); // blank layer exists
    });
  });
}
