import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A logical annotation layer (Phase 32).
///
/// Annotations are grouped by [kind] (text, shapes, images, stamps, forms,
/// strokes); each group can be shown/hidden, locked, and reordered. Opacity
/// applies to the entire layer's render.
class AnnotationLayer {
  final String id;
  final String label;
  final String kind;
  final bool visible;
  final bool locked;
  final double opacity;
  final int itemCount;

  const AnnotationLayer({
    required this.id,
    required this.label,
    required this.kind,
    this.visible = true,
    this.locked = false,
    this.opacity = 1.0,
    this.itemCount = 0,
  });

  AnnotationLayer copyWith({
    bool? visible,
    bool? locked,
    double? opacity,
    int? itemCount,
  }) =>
      AnnotationLayer(
        id: id,
        label: label,
        kind: kind,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        opacity: opacity ?? this.opacity,
        itemCount: itemCount ?? this.itemCount,
      );
}

/// UI state for the layer panel (Phase 32).
class EditorLayerState {
  final bool visible;
  final List<AnnotationLayer> layers;

  const EditorLayerState({
    this.visible = false,
    this.layers = const [],
  });

  bool get hasLayers => layers.isNotEmpty;

  /// IDs of layers that are currently visible.
  Set<String> get visibleLayerIds => {
        for (final l in layers)
          if (l.visible) l.id,
      };

  /// IDs of layers that are currently locked.
  Set<String> get lockedLayerIds => {
        for (final l in layers)
          if (l.locked) l.id,
      };

  EditorLayerState copyWith({
    bool? visible,
    List<AnnotationLayer>? layers,
  }) =>
      EditorLayerState(
        visible: visible ?? this.visible,
        layers: layers ?? this.layers,
      );
}

/// Controller for the annotation layer panel (Phase 32).
///
/// Layers are derived from annotation types on the current page. The panel lets
/// the user show/hide, lock/unlock, adjust opacity, and reorder layers.
/// Visibility and lock states feed back into the editor's selection and render
/// logic: hidden layers aren't painted, locked layers can't be selected/moved.
final editorLayerProvider =
    StateNotifierProvider<EditorLayerController, EditorLayerState>(
        (ref) => EditorLayerController());

class EditorLayerController extends StateNotifier<EditorLayerState> {
  EditorLayerController() : super(const EditorLayerState());

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  /// Rebuild layers from the annotation kinds present on the current page.
  ///
  /// [kindCounts] maps annotation kind strings (e.g. "text", "shape",
  /// "stroke", "image", "stamp", "form") to their count on this page.
  void rebuild(Map<String, int> kindCounts) {
    // Preserve existing visibility/lock/opacity for kinds that still exist.
    final existing = {for (final l in state.layers) l.kind: l};
    final layers = <AnnotationLayer>[];
    for (final entry in kindCounts.entries) {
      final kind = entry.key;
      final prev = existing[kind];
      layers.add(AnnotationLayer(
        id: 'layer_$kind',
        label: _labelFor(kind),
        kind: kind,
        visible: prev?.visible ?? true,
        locked: prev?.locked ?? false,
        opacity: prev?.opacity ?? 1.0,
        itemCount: entry.value,
      ));
    }
    state = state.copyWith(layers: layers);
  }

  void toggleVisibility(String layerId) {
    state = state.copyWith(
      layers: [
        for (final l in state.layers)
          if (l.id == layerId) l.copyWith(visible: !l.visible) else l,
      ],
    );
  }

  void toggleLock(String layerId) {
    state = state.copyWith(
      layers: [
        for (final l in state.layers)
          if (l.id == layerId) l.copyWith(locked: !l.locked) else l,
      ],
    );
  }

  void setOpacity(String layerId, double opacity) {
    state = state.copyWith(
      layers: [
        for (final l in state.layers)
          if (l.id == layerId)
            l.copyWith(opacity: opacity.clamp(0.0, 1.0))
          else
            l,
      ],
    );
  }

  void showAll() {
    state = state.copyWith(
      layers: [for (final l in state.layers) l.copyWith(visible: true)],
    );
  }

  void hideAll() {
    state = state.copyWith(
      layers: [for (final l in state.layers) l.copyWith(visible: false)],
    );
  }

  /// Reorder: move the layer at [oldIndex] to [newIndex].
  void reorder(int oldIndex, int newIndex) {
    final list = [...state.layers];
    final item = list.removeAt(oldIndex);
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    list.insert(adjusted, item);
    state = state.copyWith(layers: list);
  }

  static String _labelFor(String kind) {
    switch (kind) {
      case 'text':
        return 'Text';
      case 'shape':
        return 'Shapes';
      case 'stroke':
        return 'Drawings';
      case 'image':
        return 'Images';
      case 'stamp':
        return 'Stamps';
      case 'form':
        return 'Form Fields';
      default:
        return kind[0].toUpperCase() + kind.substring(1);
    }
  }
}
