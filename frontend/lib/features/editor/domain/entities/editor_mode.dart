import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';

/// The editor's workspaces. Each one shows only the tools for its job, so
/// the screen never carries every tool at once.
enum EditorMode {
  /// Reading: full screen, a tap shows or hides the bars.
  view,

  /// Highlights, ink, shapes, notes and stamps.
  annotate,

  /// Changing the document's own text and adding new text.
  text,

  /// Form fields, ticks, dates and signatures.
  sign,

  /// Page order, rotation and page operations.
  pages;

  /// The workspace a tool belongs to, so picking a tool (also from a
  /// keyboard shortcut) shows the bar it lives in.
  static EditorMode forTool(EditTool tool) => switch (tool) {
        EditTool.pan => EditorMode.view,
        EditTool.text => EditorMode.text,
        EditTool.check || EditTool.cross || EditTool.checkbox => EditorMode.sign,
        _ => EditorMode.annotate,
      };
}
