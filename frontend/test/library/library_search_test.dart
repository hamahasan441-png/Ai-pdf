import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/library/domain/entities/library_item.dart';
import 'package:ai_pdf/features/library/domain/services/library_search_service.dart';

LibraryItem _item(
  String name, {
  LibraryItemType type = LibraryItemType.pdf,
  String? folderId,
  Set<String> tags = const {},
  bool isFavorite = false,
  bool isPinned = false,
  int sizeBytes = 1000,
  DateTime? modified,
}) =>
    LibraryItem(
      id: 'id_$name',
      name: name,
      path: '/docs/$name',
      type: type,
      sizeBytes: sizeBytes,
      createdAt: DateTime(2024, 1, 1),
      modifiedAt: modified ?? DateTime(2024, 6, 15),
      folderId: folderId,
      tags: tags,
      isFavorite: isFavorite,
      isPinned: isPinned,
    );

void main() {
  const svc = LibrarySearchService();

  final items = [
    _item('Contract.pdf', tags: {'work', 'legal'}, sizeBytes: 5000,
        modified: DateTime(2024, 7, 1)),
    _item('Photo.jpg', type: LibraryItemType.image, sizeBytes: 2000,
        modified: DateTime(2024, 6, 1)),
    _item('Scan_receipt.pdf', type: LibraryItemType.scan, folderId: 'f1',
        tags: {'receipts'}, modified: DateTime(2024, 8, 1)),
    _item('Notes.pdf', isFavorite: true, isPinned: true, sizeBytes: 500,
        modified: DateTime(2024, 5, 1)),
  ];

  group('LibrarySearchService', () {
    test('no filter returns all items sorted by date desc (default)', () {
      final r = svc.apply(items, const LibraryQuery());
      // Pinned first, then by date descending.
      expect(r[0].name, 'Notes.pdf'); // pinned
      expect(r[1].name, 'Scan_receipt.pdf'); // Aug
      expect(r[2].name, 'Contract.pdf'); // Jul
      expect(r[3].name, 'Photo.jpg'); // Jun
    });

    test('search by name (case-insensitive substring)', () {
      final r = svc.apply(items, const LibraryQuery(searchText: 'contract'));
      expect(r.length, 1);
      expect(r.single.name, 'Contract.pdf');
    });

    test('search by tag', () {
      final r = svc.apply(items, const LibraryQuery(searchText: 'receipts'));
      expect(r.single.name, 'Scan_receipt.pdf');
    });

    test('filter by folder', () {
      final r = svc.apply(items, const LibraryQuery(folderId: 'f1'));
      expect(r.single.name, 'Scan_receipt.pdf');
    });

    test('filter by type', () {
      final r = svc.apply(
          items, const LibraryQuery(typeFilter: LibraryItemType.image));
      expect(r.single.name, 'Photo.jpg');
    });

    test('filter favorites only', () {
      final r = svc.apply(items, const LibraryQuery(favoritesOnly: true));
      expect(r.single.name, 'Notes.pdf');
    });

    test('filter by tags (any match)', () {
      final r = svc.apply(items, const LibraryQuery(tags: {'legal'}));
      expect(r.single.name, 'Contract.pdf');
    });

    test('sort by size ascending', () {
      final r = svc.apply(
        items,
        const LibraryQuery(
            sortBy: LibrarySortField.size,
            sortOrder: LibrarySortOrder.ascending),
      );
      // Pinned first regardless, then ascending size.
      // After pinned (Notes 500): Scan 1000, Photo 2000, Contract 5000.
      expect(r[0].name, 'Notes.pdf'); // pinned (500)
      expect(r[1].name, 'Scan_receipt.pdf'); // 1000
      expect(r[2].name, 'Photo.jpg'); // 2000
      expect(r[3].name, 'Contract.pdf'); // 5000
    });

    test('sort by name ascending', () {
      final r = svc.apply(
        items,
        const LibraryQuery(
            sortBy: LibrarySortField.name,
            sortOrder: LibrarySortOrder.ascending),
      );
      expect(r[0].name, 'Notes.pdf'); // pinned first
      expect(r[1].name, 'Contract.pdf');
      expect(r[2].name, 'Photo.jpg');
      expect(r[3].name, 'Scan_receipt.pdf');
    });

    test('combined: search + type filter', () {
      final r = svc.apply(
        items,
        const LibraryQuery(searchText: 'pdf', typeFilter: LibraryItemType.pdf),
      );
      // Only PDFs whose name contains "pdf"
      expect(r.every((i) => i.isPdf), isTrue);
    });

    test('empty search returns everything', () {
      final r = svc.apply(items, const LibraryQuery(searchText: ''));
      expect(r.length, items.length);
    });

    test('allTags collects from all items', () {
      expect(svc.allTags(items), {'work', 'legal', 'receipts'});
    });
  });
}
