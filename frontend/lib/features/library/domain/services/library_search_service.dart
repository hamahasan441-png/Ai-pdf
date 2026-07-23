import 'package:ai_pdf/features/library/domain/entities/library_item.dart';

/// How to sort library results.
enum LibrarySortField { name, date, size, lastOpened }
enum LibrarySortOrder { ascending, descending }

/// A filter/search configuration for the library.
class LibraryQuery {
  final String? searchText;
  final String? folderId;
  final Set<String>? tags;
  final LibraryItemType? typeFilter;
  final bool favoritesOnly;
  final LibrarySortField sortBy;
  final LibrarySortOrder sortOrder;

  const LibraryQuery({
    this.searchText,
    this.folderId,
    this.tags,
    this.typeFilter,
    this.favoritesOnly = false,
    this.sortBy = LibrarySortField.date,
    this.sortOrder = LibrarySortOrder.descending,
  });

  bool get hasActiveFilters =>
      searchText != null ||
      folderId != null ||
      (tags != null && tags!.isNotEmpty) ||
      typeFilter != null ||
      favoritesOnly;

  LibraryQuery copyWith({
    String? searchText,
    String? folderId,
    Set<String>? tags,
    LibraryItemType? typeFilter,
    bool? favoritesOnly,
    LibrarySortField? sortBy,
    LibrarySortOrder? sortOrder,
    bool clearSearch = false,
    bool clearFolder = false,
    bool clearTags = false,
    bool clearType = false,
  }) =>
      LibraryQuery(
        searchText: clearSearch ? null : (searchText ?? this.searchText),
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        tags: clearTags ? null : (tags ?? this.tags),
        typeFilter: clearType ? null : (typeFilter ?? this.typeFilter),
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        sortBy: sortBy ?? this.sortBy,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// Pure-logic search, filter, and sort for the document library.
///
/// Operates on an in-memory list (the library is small enough — typically
/// hundreds of items max — that SQL isn't needed for query performance).
/// Case-insensitive substring matching on name + tags. Deterministic sort
/// with a secondary tie-breaker (name).
class LibrarySearchService {
  const LibrarySearchService();

  /// Apply [query] to [items] and return the filtered, sorted result.
  List<LibraryItem> apply(List<LibraryItem> items, LibraryQuery query) {
    var result = items;

    // Filter: folder
    if (query.folderId != null) {
      result = result.where((i) => i.folderId == query.folderId).toList();
    }

    // Filter: type
    if (query.typeFilter != null) {
      result = result.where((i) => i.type == query.typeFilter).toList();
    }

    // Filter: favorites
    if (query.favoritesOnly) {
      result = result.where((i) => i.isFavorite).toList();
    }

    // Filter: tags (any match)
    if (query.tags != null && query.tags!.isNotEmpty) {
      result = result
          .where((i) => i.tags.any((t) => query.tags!.contains(t)))
          .toList();
    }

    // Search: name + tags
    if (query.searchText != null && query.searchText!.trim().isNotEmpty) {
      final needle = query.searchText!.toLowerCase().trim();
      result = result.where((i) {
        if (i.name.toLowerCase().contains(needle)) return true;
        if (i.tags.any((t) => t.toLowerCase().contains(needle))) return true;
        return false;
      }).toList();
    }

    // Sort
    result = [...result]..sort((a, b) {
        // Pinned items always first.
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;

        final cmp = _compare(a, b, query.sortBy);
        final ordered =
            query.sortOrder == LibrarySortOrder.ascending ? cmp : -cmp;
        // Tie-break by name.
        return ordered != 0 ? ordered : a.name.compareTo(b.name);
      });

    return result;
  }

  /// All unique tags across all items (for the filter chip list).
  Set<String> allTags(List<LibraryItem> items) =>
      {for (final i in items) ...i.tags};

  int _compare(LibraryItem a, LibraryItem b, LibrarySortField field) {
    switch (field) {
      case LibrarySortField.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case LibrarySortField.date:
        return a.modifiedAt.compareTo(b.modifiedAt);
      case LibrarySortField.size:
        return a.sizeBytes.compareTo(b.sizeBytes);
      case LibrarySortField.lastOpened:
        final aTime = a.lastOpenedAt ?? a.createdAt;
        final bTime = b.lastOpenedAt ?? b.createdAt;
        return aTime.compareTo(bTime);
    }
  }
}
