import 'dart:ui' show Color, Offset;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Sticky note colors matching popular PDF readers.
enum StickyNoteColor {
  yellow(Color(0xFFFFF176)),
  blue(Color(0xFF90CAF9)),
  green(Color(0xFFA5D6A7)),
  pink(Color(0xFFF48FB1)),
  orange(Color(0xFFFFCC80));

  final Color value;
  const StickyNoteColor(this.value);
}

/// A sticky note annotation — a small colored square (icon) on the page that
/// expands into a text note on tap. Standard PDF annotation type used for
/// review comments, reminders, and collaborative feedback.
///
/// Position is normalized (0..1). The icon is fixed-size on screen (doesn't
/// scale with zoom); the expanded note shows the full [text] content.
class StickyNoteAnnotation extends EditorAnnotation {
  /// Position of the sticky note icon (normalized 0..1).
  Offset pos;

  /// The note content text.
  String text;

  /// Visual color of the note.
  StickyNoteColor color;

  /// Author name (for collaborative workflows).
  String author;

  /// Creation timestamp (ISO 8601).
  String createdAt;

  /// Whether the note is currently expanded (UI-only state, not serialized).
  bool expanded;

  StickyNoteAnnotation({
    required this.pos,
    required this.text,
    this.color = StickyNoteColor.yellow,
    this.author = '',
    String? createdAt,
    this.expanded = false,
    String? id,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        super(id: id);

  @override
  EditorAnnotation clone() => StickyNoteAnnotation(
        pos: pos,
        text: text,
        color: color,
        author: author,
        createdAt: createdAt,
        id: id,
      )
        ..opacity = opacity
        ..locked = locked
        ..visible = visible
        ..zIndex = zIndex
        ..metadata = Map.from(metadata);
}
