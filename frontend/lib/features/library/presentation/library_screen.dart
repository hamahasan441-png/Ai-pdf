import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_pdf/core/utils/error_text.dart';
import 'package:ai_pdf/features/library/application/library_controller.dart';
import 'package:ai_pdf/features/library/domain/entities/library_folder.dart';
import 'package:ai_pdf/features/library/domain/entities/library_item.dart';
import 'package:ai_pdf/features/library/domain/services/library_search_service.dart';
import 'package:ai_pdf/features/library/presentation/widgets/library_item_tile.dart';
import 'package:ai_pdf/features/library/presentation/widgets/library_folder_chips.dart';
import 'package:ai_pdf/features/tools/services/offline_pdf_service.dart';

/// Picks the files to import; the system file picker by default.
typedef LibraryFilePicker = Future<List<({String path, String name})>> Function();

/// Counts a PDF's pages for the list; pdfx by default.
typedef LibraryPageCounter = Future<int> Function(String path);

/// The document library: the user's own copies of their PDFs and images,
/// with search, folders, filters, sorting, pins, favourites and batch
/// actions. Tapping a document opens it in the editor.
class LibraryScreen extends ConsumerStatefulWidget {
  final LibraryFilePicker? pickFiles;
  final LibraryPageCounter? countPages;

  const LibraryScreen({super.key, this.pickFiles, this.countPages});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final controller = ref.read(libraryControllerProvider.notifier);

    return Scaffold(
      appBar: _buildAppBar(state, controller),
      body: Column(
        children: [
          if (_showSearch) _searchBar(controller, cs),
          if (state.error != null) _errorBanner(state.error!, controller, cs),
          LibraryFolderChips(
            folders: state.folders,
            activeFolderId: state.query.folderId,
            onFolderTap: controller.filterByFolder,
            onCreateFolder: () => _createFolderDialog(controller),
            onRenameFolder: (f) => _renameFolderDialog(f, controller),
            onDeleteFolder: (f) => _deleteFolderDialog(f, controller),
          ),
          _filterRow(state, controller, cs),
          if (_importing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.filteredItems.isEmpty
                    ? _empty(state, controller, cs)
                    : _itemList(state, controller),
          ),
        ],
      ),
      floatingActionButton: state.multiSelectMode
          ? null
          : FloatingActionButton(
              onPressed: _importing ? null : () => _importDocuments(controller),
              tooltip: _l10n.libImport,
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: state.multiSelectMode ? _multiSelectBar(state, controller, cs) : null,
    );
  }

  PreferredSizeWidget _buildAppBar(LibraryState state, LibraryController controller) {
    final l10n = _l10n;
    if (state.multiSelectMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: controller.exitMultiSelect,
        ),
        title: Text(l10n.libSelectedCount(state.selectedCount)),
        actions: [
          TextButton(onPressed: controller.selectAll, child: Text(l10n.libSelectAll)),
        ],
      );
    }
    return AppBar(
      title: Text(l10n.libTitle),
      actions: [
        IconButton(
          icon: Icon(_showSearch ? Icons.search_off : Icons.search),
          tooltip: _showSearch ? l10n.libCloseSearch : l10n.libSearch,
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) {
              _searchController.clear();
              controller.search(null);
            }
          }),
        ),
        PopupMenuButton<String>(
          tooltip: l10n.libMore,
          onSelected: (v) {
            if (v == 'multi') controller.enterMultiSelect();
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'multi', child: Text(l10n.libSelectMultiple)),
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
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: _l10n.libSearchHint,
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

  Widget _errorBanner(Object error, LibraryController controller, ColorScheme cs) {
    return MaterialBanner(
      backgroundColor: cs.errorContainer,
      leading: Icon(Icons.error_outline, color: cs.onErrorContainer),
      content: Text(
        _l10n.libLoadFailed(describeError(error, _l10n)),
        style: TextStyle(color: cs.onErrorContainer),
      ),
      actions: [TextButton(onPressed: controller.load, child: Text(_l10n.libRetry))],
    );
  }

  Widget _filterRow(LibraryState state, LibraryController controller, ColorScheme cs) {
    final l10n = _l10n;
    final type = state.query.typeFilter;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8, top: 4, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _typeChip(l10n.libAll, type == null, () => controller.filterByType(null), cs),
                _typeChip(l10n.libPdf, type == LibraryItemType.pdf, () => controller.filterByType(LibraryItemType.pdf), cs),
                _typeChip(l10n.libImages, type == LibraryItemType.image, () => controller.filterByType(LibraryItemType.image), cs),
                _typeChip(l10n.libScans, type == LibraryItemType.scan, () => controller.filterByType(LibraryItemType.scan), cs),
              ]),
            ),
          ),
          IconButton(
            icon: Icon(
              state.query.favoritesOnly ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: state.query.favoritesOnly ? cs.error : cs.onSurfaceVariant,
            ),
            isSelected: state.query.favoritesOnly,
            tooltip: l10n.libFavoritesOnly,
            onPressed: controller.toggleFavoritesFilter,
          ),
          PopupMenuButton<LibrarySortField>(
            icon: const Icon(Icons.sort, size: 20),
            tooltip: l10n.libSort,
            onSelected: (f) => controller.setSort(f),
            itemBuilder: (_) => [
              _sortItem(LibrarySortField.date, l10n.libSortDate, state),
              _sortItem(LibrarySortField.name, l10n.libSortName, state),
              _sortItem(LibrarySortField.size, l10n.libSortSize, state),
              _sortItem(LibrarySortField.lastOpened, l10n.libSortOpened, state),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<LibrarySortField> _sortItem(LibrarySortField field, String label, LibraryState state) {
    final active = state.query.sortBy == field;
    return PopupMenuItem(
      value: field,
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: active ? FontWeight.bold : null))),
          if (active)
            Icon(
              state.query.sortOrder == LibrarySortOrder.ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
            ),
        ],
      ),
    );
  }

  Widget _typeChip(String label, bool active, VoidCallback onTap, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: FilterChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        selectedColor: cs.primaryContainer,
      ),
    );
  }

  Widget _itemList(LibraryState state, LibraryController controller) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: state.filteredItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final item = state.filteredItems[i];
        return LibraryItemTile(
          key: ValueKey(item.id),
          item: item,
          selected: state.selectedIds.contains(item.id),
          multiSelectMode: state.multiSelectMode,
          onTap: () {
            if (state.multiSelectMode) {
              controller.toggleSelection(item.id);
            } else {
              _open(item, controller);
            }
          },
          onLongPress: () {
            if (!state.multiSelectMode) {
              controller.enterMultiSelect();
              controller.toggleSelection(item.id);
            }
          },
          onFavorite: () => controller.toggleFavorite(item.id),
          onAction: (a) => _itemAction(a, item, state, controller),
        );
      },
    );
  }

  Widget _empty(LibraryState state, LibraryController controller, ColorScheme cs) {
    final l10n = _l10n;
    final filtering = state.items.isNotEmpty && state.query.hasActiveFilters;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(filtering ? Icons.search_off : Icons.folder_open,
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(filtering ? l10n.libNoMatches : l10n.libEmptyTitle,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            if (filtering)
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  controller.clearFilters();
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: Text(l10n.libClearFilters),
              )
            else ...[
              Text(l10n.libEmptyBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.8))),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _importing ? null : () => _importDocuments(controller),
                icon: const Icon(Icons.file_upload_outlined),
                label: Text(l10n.libImport),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _multiSelectBar(LibraryState state, LibraryController controller, ColorScheme cs) {
    final l10n = _l10n;
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined),
            tooltip: l10n.libMoveToFolder,
            onPressed: state.hasSelection
                ? () async {
                    final folder = await _pickFolder(state);
                    if (folder != null) await controller.moveSelectedToFolder(folder.id);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            tooltip: l10n.libFavorite,
            onPressed: state.hasSelection
                ? () async {
                    // Favourite them all, unless all already are: then unfavourite.
                    final chosen = [for (final i in state.items) if (state.selectedIds.contains(i.id)) i];
                    final target = !chosen.every((i) => i.isFavorite);
                    for (final i in chosen) {
                      if (i.isFavorite != target) await controller.toggleFavorite(i.id);
                    }
                    controller.exitMultiSelect();
                  }
                : null,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: state.hasSelection ? cs.error : null),
            tooltip: l10n.delete,
            onPressed: state.hasSelection
                ? () async {
                    if (await _confirmDelete(l10n.libDeleteMany(state.selectedCount))) {
                      await controller.deleteSelected();
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _open(LibraryItem item, LibraryController controller) async {
    if (!await File(item.path).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_l10n.libFileGone),
        action: SnackBarAction(label: _l10n.libRemoveEntry, onPressed: () => controller.removeItem(item.id)),
      ));
      return;
    }
    await controller.markOpened(item.id);
    if (mounted) context.push('/tools/pick-edit', extra: item.path);
  }

  Future<void> _itemAction(
      LibraryItemAction action, LibraryItem item, LibraryState state, LibraryController controller) async {
    switch (action) {
      case LibraryItemAction.rename:
        final name = await _askName(_l10n.libRename, item.name, _l10n.save, hint: _l10n.libSortName);
        if (name != null && name != item.name) await controller.renameItem(item.id, name);
      case LibraryItemAction.pin:
        await controller.togglePin(item.id);
      case LibraryItemAction.move:
        final folder = await _pickFolder(state);
        if (folder != null) await controller.moveToFolder(item.id, folder.id);
      case LibraryItemAction.delete:
        if (await _confirmDelete(_l10n.libDeleteOne(item.name))) await controller.removeItem(item.id);
    }
  }

  Future<void> _importDocuments(LibraryController controller) async {
    final List<({String path, String name})> files;
    try {
      files = await (widget.pickFiles ?? _systemPick)();
    } catch (e) {
      _snack(describeError(e, _l10n));
      return;
    }
    if (files.isEmpty || !mounted) return;
    setState(() => _importing = true);
    var added = 0;
    final failures = <String>[];
    for (final f in files) {
      try {
        final pages = LibraryController.typeOf(f.name) == LibraryItemType.pdf
            ? await (widget.countPages ?? OfflinePdfService.instance.getPageCount)(f.path)
            : 1;
        await controller.importFile(f.path, f.name, pageCount: pages);
        added++;
      } catch (e) {
        if (!mounted) return;
        failures.add(_l10n.libImportFailed(f.name, describeError(e, _l10n)));
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    _snack([if (added > 0) _l10n.libImported(added), ...failures].join('\n'));
  }

  static Future<List<({String path, String name})>> _systemPick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    return [
      for (final f in result?.files ?? const <PlatformFile>[])
        if (f.path != null) (path: f.path!, name: f.name),
    ];
  }

  void _snack(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmDelete(String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
        title: Text(title),
        content: Text(_l10n.libDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_l10n.delete),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Ask for a name; null when cancelled or left blank.
  Future<String?> _askName(String title, String initial, String confirm, {String? hint}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameDialog(title: title, initial: initial, hint: hint ?? _l10n.libFolderName, confirm: confirm),
    );
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Choose a folder; "no folder" comes back as a folder with an empty id.
  Future<({String? id})?> _pickFolder(LibraryState state) {
    return showDialog<({String? id})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_l10n.libMoveToFolder),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, (id: null)),
            child: Row(children: [const Icon(Icons.folder_off_outlined, size: 20), const SizedBox(width: 12), Text(_l10n.libNoFolder)]),
          ),
          for (final f in state.folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, (id: f.id)),
              child: Row(children: [
                const Icon(Icons.folder_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(f.name, overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _createFolderDialog(LibraryController controller) async {
    final name = await _askName(_l10n.libNewFolder, '', _l10n.libCreate);
    if (name != null) await controller.createFolder(name);
  }

  Future<void> _renameFolderDialog(LibraryFolder folder, LibraryController controller) async {
    final name = await _askName(_l10n.libRenameFolder, folder.name, _l10n.save);
    if (name != null && name != folder.name) await controller.renameFolder(folder.id, name);
  }

  Future<void> _deleteFolderDialog(LibraryFolder folder, LibraryController controller) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.libDeleteFolder),
        content: Text(_l10n.libDeleteFolderBody(folder.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_l10n.delete)),
        ],
      ),
    );
    if (ok ?? false) {
      if (ref.read(libraryControllerProvider).query.folderId == folder.id) controller.filterByFolder(null);
      await controller.deleteFolder(folder.id);
    }
  }
}

/// A name field that owns its controller, so it outlives the closing
/// animation.
class _NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String hint;
  final String confirm;

  const _NameDialog({required this.title, required this.initial, required this.hint, required this.confirm});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('libraryName'),
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: Text(widget.confirm)),
      ],
    );
  }
}
