import 'package:flutter/material.dart';

import 'package:ai_pdf/features/library/domain/entities/library_folder.dart';

/// Horizontal scrollable row of folder filter chips + a "create" button.
class LibraryFolderChips extends StatelessWidget {
  final List<LibraryFolder> folders;
  final String? activeFolderId;
  final ValueChanged<String?> onFolderTap;
  final VoidCallback onCreateFolder;

  const LibraryFolderChips({
    super.key,
    required this.folders,
    required this.activeFolderId,
    required this.onFolderTap,
    required this.onCreateFolder,
  });

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip('All', activeFolderId == null, () => onFolderTap(null), cs),
          for (final f in folders)
            _chip(f.name, activeFolderId == f.id, () => onFolderTap(f.id), cs),
          ActionChip(
            avatar: const Icon(Icons.add, size: 14),
            label: const Text('New', style: TextStyle(fontSize: 11)),
            onPressed: onCreateFolder,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _chip(
      String label, bool active, VoidCallback onTap, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: cs.primaryContainer,
        visualDensity: VisualDensity.compact,
        avatar: active ? null : const Icon(Icons.folder_outlined, size: 14),
      ),
    );
  }
}
