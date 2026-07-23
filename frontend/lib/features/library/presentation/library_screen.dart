import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_pdf/features/library/application/library_controller.dart';
import 'package:ai_pdf/features/library/domain/entities/library_item.dart';
import 'package:ai_pdf/features/library/domain/services/library_search_service.dart';
import 'package:ai_pdf/features/library/presentation/widgets/library_item_tile.dart';
import 'package:ai_pdf/features/library/presentation/widgets/library_folder_chips.dart';

/// The document library screen — the user's personal document hub.
///
/// Shows all stored documents (PDFs, images, scans) with search, folder filter,
/// sort options, multi-select batch operations, and quick actions. This is what
/// transforms the app from a "tool" into a "platform."
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    // Load library on first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final controller = ref.read(libraryControllerProvider.notifier);

    return Scaffold(
      appBar: _buildAppBar(state, controller, cs),
      body: Column(
        children: [
          if (_showSearch) _searchBar(controller, cs),
          LibraryFolderChips(
            folders: state.folders,
            activeFolderId: state.query.folderId,
            onFolderTap: controller.filterByFolder,
            onCreateFolder: () => _createFolderDialog(controller),
          ),
          _filterRow(state, controller, cs),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.filteredItems.isEmpty
                    ? _empty(cs)
                    : _itemList(state, controller, cs),
          ),
        ],
      ),
      floatingActionButton: state.multiSelectMode
          ? null
          : FloatingActionButton(
              onPressed: () => _importDocument(controller),
              tooltip: 'Import document',
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: state.multiSelectMode
          ? _multiSelectBar(state, controller, cs)
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(
      LibraryState state, LibraryController controller, ColorScheme cs) {
    if (state.multiSelectMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: controller.exitMultiSelect,
        ),
        title: Text('${state.selectedCount} selected'),
        actions: [
          TextButton(
            onPressed: controller.selectAll,
            child: const Text('Select all'),
          ),
        ],
      );
    }
    return AppBar(
      title: const Text('My Documents'),
      actions: [
        IconButton(
          icon: Icon(_showSearch ? Icons.search_off : Icons.search),
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) {
              _searchController.clear();
              controller.search(null);
            }
          }),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'multi') controller.enterMultiSelect();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'multi', child: Text('Select multiple')),
          ],
        ),
      ],
    );
  }

  Widget _searchBar(LibraryController controller, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search documents...',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: cs.surfaceContainerHighest,
        ),
        onChanged: controller.search,
      ),
    );
  }

  Widget _filterRow(
      LibraryState state, LibraryController controller, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Type chips
          _typeChip('All', state.query.typeFilter == null,
              () => controller.filterByType(null), cs),
          _typeChip('PDF', state.query.typeFilter == LibraryItemType.pdf,
              () => controller.filterByType(LibraryItemType.pdf), cs),
          _typeChip('Images', state.query.typeFilter == LibraryItemType.image,
              () => controller.filterByType(LibraryItemType.image), cs),
          _typeChip('Scans', state.query.typeFilter == LibraryItemType.scan,
              () => controller.filterByType(LibraryItemType.scan), cs),
          const Spacer(),
          // Favorites toggle
          IconButton(
            icon: Icon(
              state.query.favoritesOnly ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: state.query.favoritesOnly ? Colors.red : cs.onSurfaceVariant,
            ),
            onPressed: controller.toggleFavoritesFilter,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          // Sort
          PopupMenuButton<LibrarySortField>(
            icon: const Icon(Icons.sort, size: 20),
            onSelected: (f) => controller.setSort(f),
            itemBuilder: (_) => [
              _sortItem(LibrarySortField.date, 'Date modified', state),
              _sortItem(LibrarySortField.name, 'Name', state),
              _sortItem(LibrarySortField.size, 'Size', state),
              _sortItem(LibrarySortField.lastOpened, 'Last opened', state),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<LibrarySortField> _sortItem(
      LibrarySortField field, String label, LibraryState state) {
    final active = state.query.sortBy == field;
    return PopupMenuItem(
      value: field,
      child: Row(
        children: [
          Text(label, style: TextStyle(fontWeight: active ? FontWeight.bold : null)),
          if (active) ...[
            const Spacer(),
            Icon(
              state.query.sortOrder == LibrarySortOrder.ascending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 16,
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeChip(
      String label, bool active, VoidCallback onTap, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: active,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        selectedColor: cs.primaryContainer,
      ),
    );
  }

  Widget _itemList(
      LibraryState state, LibraryController controller, ColorScheme cs) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: state.filteredItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final item = state.filteredItems[i];
        return LibraryItemTile(
          item: item,
          selected: state.selectedIds.contains(item.id),
          multiSelectMode: state.multiSelectMode,
          onTap: () {
            if (state.multiSelectMode) {
              controller.toggleSelection(item.id);
            } else {
              controller.markOpened(item.id);
              context.push('/tools/pick-edit');
            }
          },
          onLongPress: () {
            if (!state.multiSelectMode) {
              controller.enterMultiSelect();
              controller.toggleSelection(item.id);
            }
          },
          onFavorite: () => controller.toggleFavorite(item.id),
          onDelete: () => controller.removeItem(item.id),
        );
      },
    );
  }

  Widget _empty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64, color: cs.onSurfaceVariant.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text('No documents yet',
              style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Scan, import, or create to get started',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _multiSelectBar(
      LibraryState state, LibraryController controller, ColorScheme cs) {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Move to folder',
            onPressed: state.hasSelection
                ? () => _moveToFolderDialog(state, controller)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            tooltip: 'Favorite',
            onPressed: state.hasSelection
                ? () {
                    for (final id in state.selectedIds) {
                      controller.toggleFavorite(id);
                    }
                    controller.exitMultiSelect();
                  }
                : null,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: cs.error),
            tooltip: 'Delete',
            onPressed: state.hasSelection ? controller.deleteSelected : null,
          ),
        ],
      ),
    );
  }

  void _importDocument(LibraryController controller) {
    // For now, navigate to the file picker. A full implementation would
    // import directly and register in the library.
    context.push('/tools/pick-edit');
  }

  Future<void> _createFolderDialog(LibraryController controller) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final tc = TextEditingController();
        return AlertDialog(
          title: const Text('New Folder'),
          content: TextField(
            controller: tc,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Folder name'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, tc.text),
                child: const Text('Create')),
          ],
        );
      },
    );
    if (name != null && name.trim().isNotEmpty) {
      controller.createFolder(name.trim());
    }
  }

  Future<void> _moveToFolderDialog(
      LibraryState state, LibraryController controller) async {
    final folderId = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Move to folder'),
        children: [
          SimpleDialogOption(
            child: const Text('(None)'),
            onPressed: () => Navigator.pop(ctx, '__none__'),
          ),
          for (final f in state.folders)
            SimpleDialogOption(
              child: Text(f.name),
              onPressed: () => Navigator.pop(ctx, f.id),
            ),
        ],
      ),
    );
    if (folderId != null) {
      controller.moveSelectedToFolder(folderId == '__none__' ? null : folderId);
    }
  }
}
