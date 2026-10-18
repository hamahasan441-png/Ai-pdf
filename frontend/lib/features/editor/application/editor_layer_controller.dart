import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/sticky_note_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/text_markup_annotation.dart';

/// The marks of one kind on a page (text, shapes, drawings, …), shown as one
/// row of the Layers panel.
///
/// A row is a view of the marks themselves: it is visible when every mark of
/// that kind is visible, and locked when every one is locked. Hidden marks are
/// not drawn and not exported; locked marks cannot be selected or moved.
class AnnotationLayer {
  final String kind;
  final String label;
  final bool visible;
  final bool locked;
  final int itemCount;

  const AnnotationLayer({
    required this.kind,
    required this.label,
    required this.visible,
    required this.locked,
    required this.itemCount,
  });

  String get id => 'layer_$kind';
}

class EditorLayerState {
  final bool visible;
  final List<AnnotationLayer> layers;

  const EditorLayerState({this.visible = false, this.layers = const []});

  bool get hasLayers => layers.isNotEmpty;
}

final editorLayerProvider =
    StateNotifierProvider<EditorLayerController, EditorLayerState>((ref) => EditorLayerController());

/// Shows or hides the Layers panel and applies its toggles to the marks.
///
/// Redaction covers never belong to a layer: hiding one would leave the text
/// it covers in the exported file.
class EditorLayerController extends StateNotifier<EditorLayerState> {
  EditorLayerController() : super(const EditorLayerState());

  static const order = ['text', 'shape', 'stroke', 'markup', 'image', 'stamp', 'note', 'form'];

  void show() => state = EditorLayerState(visible: true, layers: state.layers);
  void hide() => state = EditorLayerState(visible: false, layers: state.layers);
  void toggle() => state.visible ? hide() : show();

  /// Re-reads the rows from [page]. Call after any change to its marks.
  void sync(PageLayer? page) => state = EditorLayerState(visible: state.visible, layers: layersOf(page));

  /// The kind of [a] for the panel, or null for marks the panel must not
  /// touch (redaction covers).
  static String? kindOf(EditorAnnotation a) => switch (a) {
        ShapeAnnotation(burnsBlackCover: true) => null,
        TextAnnotation() => 'text',
        ShapeAnnotation() => 'shape',
        StrokeAnnotation() => 'stroke',
        TextMarkupAnnotation() => 'markup',
        ImageAnnotation() => 'image',
        StampAnnotation() => 'stamp',
        StickyNoteAnnotation() => 'note',
        FormFieldAnnotation() => 'form',
        _ => null,
      };

  static List<AnnotationLayer> layersOf(PageLayer? page) {
    final byKind = <String, List<EditorAnnotation>>{};
    for (final a in page?.items ?? const <EditorAnnotation>[]) {
      final k = kindOf(a);
      if (k != null) (byKind[k] ??= []).add(a);
    }
    return [
      for (final k in order)
        if (byKind[k] case final items?)
          AnnotationLayer(
            kind: k,
            label: _labelFor(k),
            visible: items.every((a) => a.visible),
            locked: items.every((a) => a.locked),
            itemCount: items.length,
          ),
    ];
  }

  /// The marks on [page] that a toggle of [kind] changes; null for all kinds.
  static List<EditorAnnotation> targets(PageLayer page, String? kind) => [
        for (final a in page.items)
          if (kindOf(a) case final k? when kind == null || k == kind) a,
      ];

  /// Shows every mark of [kind] if any is hidden, otherwise hides them all.
  static void toggleVisibility(PageLayer page, String kind) {
    final items = targets(page, kind);
    final show = !items.every((a) => a.visible);
    for (final a in items) {
      a.visible = show;
    }
  }

  /// Locks every mark of [kind] if any is unlocked, otherwise unlocks them.
  static void toggleLock(PageLayer page, String kind) {
    final items = targets(page, kind);
    final lock = !items.every((a) => a.locked);
    for (final a in items) {
      a.locked = lock;
    }
  }

  static void setAllVisible(PageLayer page, bool visible) {
    for (final a in targets(page, null)) {
      a.visible = visible;
    }
  }

  static String _labelFor(String kind) => switch (kind) {
        'text' => 'Text',
        'shape' => 'Shapes',
        'stroke' => 'Drawings',
        'markup' => 'Highlights',
        'image' => 'Images',
        'stamp' => 'Stamps',
        'note' => 'Notes',
        'form' => 'Form fields',
        _ => kind,
      };
}
