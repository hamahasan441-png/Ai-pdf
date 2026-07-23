import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/library/data/library_repository.dart';
import 'package:ai_pdf/features/library/domain/entities/library_folder.dart';
import 'package:ai_pdf/features/library/domain/entities/library_item.dart';
import 'package:ai_pdf/features/library/domain/services/library_search_service.dart';

/// UI state for the document library.
class LibraryState {
  final List<LibraryItem> items;
  final List<LibraryFolder> folders;
  final LibraryQuery query;
  final List<LibraryItem> filteredItems;
  final Set<String> selectedIds;
  final bool multiSelectMode;
  final bool loading;
  final String? error;

  const LibraryState({
    this.items = const [],
    this.folders = const [],
    this.query = const LibraryQuery(),
    this.filteredItems = const [],
    this.selectedIds = const {},
    this.multiSelectMode = false,
    this.loading = false,
    this.error,
  });

  int get totalCount => items.length;
  int get selectedCount => selectedIds.length;
  bool get hasSelection => selectedIds.isNotEmpty;
  Set<String> get allTags => const LibrarySearchService().allTags(items);

  LibraryState copyWith({
    List<LibraryItem>? items,
    List<LibraryFolder>? folders,
    LibraryQuery? query,
    List<LibraryItem>? filteredItems,
    Set<String>? selectedIds,
    bool? multiSelectMode,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      LibraryState(
        items: items ?? this.items,
        folders: folders ?? this.folders,
        query: query ?? this.query,
        filteredItems: filteredItems ?? this.filteredItems,
        selectedIds: selectedIds ?? this.selectedIds,
        multiSelectMode: multiSelectMode ?? this.multiSelectMode,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Controller for the document library feature.
///
/// Manages the full lifecycle: load from disk, CRUD operations on items and
/// folders, search/filter/sort, multi-select batch operations, favorites,
/// tagging. All mutations persist immediately via [LibraryRepository].
final libraryControllerProvider =
    StateNotifierProvider<LibraryController, LibraryState>(
        (ref) => LibraryController());

class LibraryController extends StateNotifier<LibraryState> {
  LibraryController() : super(const LibraryState());

  static const _repo = LibraryRepository();
  static const _search = LibrarySearchService();
  int _seq = 1;

  /// Load the library from disk. Call once at startup.
  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final items = await _repo.loadItems();
      final folders = await _repo.loadFolders();
      state = state.copyWith(
        items: items,
        folders: folders,
        loading: false,
      );
      _refilter();
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Load failed: $e');
    }
  }

  // ── Query ─────────────────────────────────────────────────────────────

  void setQuery(LibraryQuery query) {
    state = state.copyWith(query: query);
    _refilter();
  }

  void search(String? text) {
    setQuery(state.query.copyWith(
        searchText: text, clearSearch: text == null || text.isEmpty));
  }

  void filterByFolder(String? folderId) {
    setQuery(state.query.copyWith(folderId: folderId, clearFolder: folderId == null));
  }

  void filterByType(LibraryItemType? type) {
    setQuery(state.query.copyWith(typeFilter: type, clearType: type == null));
  }

  void toggleFavoritesFilter() {
    setQuery(state.query.copyWith(favoritesOnly: !state.query.favoritesOnly));
  }

  void setSort(LibrarySortField field, {LibrarySortOrder? order}) {
    final newOrder = order ??
        (state.query.sortBy == field
            ? (state.query.sortOrder == LibrarySortOrder.ascending
                ? LibrarySortOrder.descending
                : LibrarySortOrder.ascending)
            : LibrarySortOrder.descending);
    setQuery(state.query.copyWith(sortBy: field, sortOrder: newOrder));
  }

  void clearFilters() => setQuery(const LibraryQuery());

  // ── Items ─────────────────────────────────────────────────────────────

  /// Add a new item to the library (after import/scan/create).
  Future<LibraryItem> addItem({
    required String name,
    required String path,
    required LibraryItemType type,
    int sizeBytes = 0,
    int pageCount = 1,
    String? folderId,
  }) async {
    final item = LibraryItem(
      id: 'lib_${_seq++}_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      path: path,
      type: type,
      sizeBytes: sizeBytes,
      pageCount: pageCount,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      folderId: folderId,
    );
    final items = [item, ...state.items];
    state = state.copyWith(items: items);
    _refilter();
    await _repo.saveItems(items);
    return item;
  }

  Future<void> removeItem(String id) async {
    final item = state.items.cast<LibraryItem?>().firstWhere(
        (i) => i?.id == id,
        orElse: () => null);
    if (item != null) {
      await _repo.deleteFile(item.path);
    }
    final items = [for (final i in state.items) if (i.id != id) i];
    state = state.copyWith(
      items: items,
      selectedIds: {...state.selectedIds}..remove(id),
    );
    _refilter();
    await _repo.saveItems(items);
  }

  Future<void> renameItem(String id, String newName) async {
    await _mutateItem(id, (i) => i.copyWith(name: newName, modifiedAt: DateTime.now()));
  }

  Future<void> toggleFavorite(String id) async {
    await _mutateItem(id, (i) => i.copyWith(isFavorite: !i.isFavorite));
  }

  Future<void> togglePin(String id) async {
    await _mutateItem(id, (i) => i.copyWith(isPinned: !i.isPinned));
  }

  Future<void> moveToFolder(String id, String? folderId) async {
    await _mutateItem(id, (i) => i.copyWith(folderId: folderId, clearFolder: folderId == null));
  }

  Future<void> addTag(String id, String tag) async {
    await _mutateItem(id, (i) => i.copyWith(tags: {...i.tags, tag}));
  }

  Future<void> removeTag(String id, String tag) async {
    await _mutateItem(id, (i) => i.copyWith(tags: {...i.tags}..remove(tag)));
  }

  Future<void> markOpened(String id) async {
    await _mutateItem(id, (i) => i.copyWith(lastOpenedAt: DateTime.now()));
  }

  // ── Multi-select ────────────────────────────────────────────────────────

  void enterMultiSelect() => state = state.copyWith(multiSelectMode: true);
  void exitMultiSelect() =>
      state = state.copyWith(multiSelectMode: false, selectedIds: const {});

  void toggleSelection(String id) {
    final selected = {...state.selectedIds};
    if (selected.contains(id)) {
      selected.remove(id);
    } else {
      selected.add(id);
    }
    state = state.copyWith(selectedIds: selected);
  }

  void selectAll() {
    state = state.copyWith(
      selectedIds: {for (final i in state.filteredItems) i.id},
    );
  }

  /// Batch delete all selected items.
  Future<void> deleteSelected() async {
    for (final id in state.selectedIds) {
      final item = state.items.cast<LibraryItem?>().firstWhere(
          (i) => i?.id == id,
          orElse: () => null);
      if (item != null) await _repo.deleteFile(item.path);
    }
    final items = [
      for (final i in state.items)
        if (!state.selectedIds.contains(i.id)) i,
    ];
    state = state.copyWith(items: items, selectedIds: const {}, multiSelectMode: false);
    _refilter();
    await _repo.saveItems(items);
  }

  /// Batch move selected to a folder.
  Future<void> moveSelectedToFolder(String? folderId) async {
    final items = [
      for (final i in state.items)
        if (state.selectedIds.contains(i.id))
          i.copyWith(folderId: folderId, clearFolder: folderId == null)
        else
          i,
    ];
    state = state.copyWith(items: items, selectedIds: const {}, multiSelectMode: false);
    _refilter();
    await _repo.saveItems(items);
  }

  // ── Folders ─────────────────────────────────────────────────────────────

  Future<LibraryFolder> createFolder(String name, {String? color}) async {
    final folder = LibraryFolder(
      id: 'folder_${_seq++}_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      color: color,
      createdAt: DateTime.now(),
    );
    final folders = [...state.folders, folder];
    state = state.copyWith(folders: folders);
    await _repo.saveFolders(folders);
    return folder;
  }

  Future<void> renameFolder(String id, String newName) async {
    final folders = [
      for (final f in state.folders)
        if (f.id == id) f.copyWith(name: newName) else f,
    ];
    state = state.copyWith(folders: folders);
    await _repo.saveFolders(folders);
  }

  Future<void> deleteFolder(String id) async {
    // Items in this folder become "unfiled" (not deleted).
    final items = [
      for (final i in state.items)
        if (i.folderId == id) i.copyWith(clearFolder: true) else i,
    ];
    final folders = [for (final f in state.folders) if (f.id != id) f];
    state = state.copyWith(items: items, folders: folders);
    _refilter();
    await _repo.saveItems(items);
    await _repo.saveFolders(folders);
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<void> _mutateItem(
      String id, LibraryItem Function(LibraryItem) transform) async {
    final items = [
      for (final i in state.items)
        if (i.id == id) transform(i) else i,
    ];
    state = state.copyWith(items: items);
    _refilter();
    await _repo.saveItems(items);
  }

  void _refilter() {
    state = state.copyWith(
      filteredItems: _search.apply(state.items, state.query),
    );
  }
}
