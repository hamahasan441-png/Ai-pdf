import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/library/domain/entities/library_folder.dart';

/// Horizontal row of folder filter chips and a "new folder" chip. A long
/// press on a folder offers rename and delete.
class LibraryFolderChips extends StatelessWidget {
  final List<LibraryFolder> folders;
  final String? activeFolderId;
  final ValueChanged<String?> onFolderTap;
  final VoidCallback onCreateFolder;
  final ValueChanged<LibraryFolder> onRenameFolder;
  final ValueChanged<LibraryFolder> onDeleteFolder;

  const LibraryFolderChips({
    super.key,
    required this.folders,
    required this.activeFolderId,
    required this.onFolderTap,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onDeleteFolder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          if (folders.isNotEmpty) _chip(context, null, l10n.libAll, cs),
          for (final f in folders) _chip(context, f, f.name, cs),
          ActionChip(
            avatar: const Icon(Icons.create_new_folder_outlined, size: 16),
            label: Text(folders.isEmpty ? l10n.libNewFolder : l10n.libNew),
            tooltip: l10n.libNewFolder,
            onPressed: onCreateFolder,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, LibraryFolder? folder, String label, ColorScheme cs) {
    final active = activeFolderId == folder?.id;
    final chip = FilterChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => onFolderTap(folder?.id),
      selectedColor: cs.primaryContainer,
      visualDensity: VisualDensity.compact,
      avatar: active || folder == null ? null : const Icon(Icons.folder_outlined, size: 16),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: folder == null
          ? chip
          : GestureDetector(
              onLongPressStart: (d) => _folderMenu(context, folder, d.globalPosition),
              child: chip,
            ),
    );
  }

  Future<void> _folderMenu(BuildContext context, LibraryFolder folder, Offset at) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(value: 'rename', child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(l10n.libRenameFolder))),
        PopupMenuItem(value: 'delete', child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(l10n.libDeleteFolder))),
      ],
    );
    if (choice == 'rename') onRenameFolder(folder);
    if (choice == 'delete') onDeleteFolder(folder);
  }
}
