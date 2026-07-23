import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/sticky_note_annotation.dart';

/// Renders a sticky note annotation — a small colored icon that expands to
/// show the note text on tap.
class StickyNoteWidget extends StatelessWidget {
  final StickyNoteAnnotation note;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onTextChanged;

  const StickyNoteWidget({
    super.key,
    required this.note,
    required this.onTap,
    this.onDelete,
    this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!note.expanded) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: note.color.value,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 3,
                offset: const Offset(1, 1),
              ),
            ],
          ),
          child: const Icon(Icons.sticky_note_2, size: 16, color: Colors.black54),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        constraints: const BoxConstraints(minHeight: 80, maxHeight: 200),
        decoration: BoxDecoration(
          color: note.color.value,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  if (note.author.isNotEmpty)
                    Expanded(
                      child: Text(
                        note.author,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  if (onDelete != null)
                    GestureDetector(
                      onTap: onDelete,
                      child: const Icon(Icons.close, size: 14),
                    ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Text(
                  note.text,
                  style: const TextStyle(fontSize: 12, height: 1.3),
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
