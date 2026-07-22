import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single keyboard shortcut binding (Phase 46).
class ShortcutBinding {
  final String id;
  final String action;
  final String label;
  final String category;
  final String keys;
  final bool customizable;

  const ShortcutBinding({
    required this.id,
    required this.action,
    required this.label,
    required this.category,
    required this.keys,
    this.customizable = true,
  });

  ShortcutBinding copyWith({String? keys}) => ShortcutBinding(
        id: id,
        action: action,
        label: label,
        category: category,
        keys: keys ?? this.keys,
        customizable: customizable,
      );
}

/// UI state for the keyboard shortcuts manager (Phase 46).
class EditorShortcutsState {
  final bool visible;
  final List<ShortcutBinding> bindings;
  final String? editingId;
  final String? filterCategory;

  const EditorShortcutsState({
    this.visible = false,
    this.bindings = const [],
    this.editingId,
    this.filterCategory,
  });

  List<String> get categories => [
        ...{for (final b in bindings) b.category},
      ]..sort();

  List<ShortcutBinding> get filtered => filterCategory == null
      ? bindings
      : bindings.where((b) => b.category == filterCategory).toList();

  /// Look up the keys for an action.
  String? keysFor(String action) {
    final binding = bindings.cast<ShortcutBinding?>().firstWhere(
        (b) => b?.action == action,
        orElse: () => null);
    return binding?.keys;
  }

  EditorShortcutsState copyWith({
    bool? visible,
    List<ShortcutBinding>? bindings,
    String? editingId,
    String? filterCategory,
    bool clearEditing = false,
    bool clearFilter = false,
  }) =>
      EditorShortcutsState(
        visible: visible ?? this.visible,
        bindings: bindings ?? this.bindings,
        editingId: clearEditing ? null : (editingId ?? this.editingId),
        filterCategory:
            clearFilter ? null : (filterCategory ?? this.filterCategory),
      );
}

/// Controller for the keyboard shortcuts manager (Phase 46).
///
/// Holds all editor keyboard shortcut bindings (default + user-customized).
/// The shortcuts dialog lets the user view all bindings by category, search,
/// and reassign keys. The actual shortcut listener (Focus + RawKeyboardListener)
/// queries this controller to map key combos → actions.
final editorShortcutsProvider =
    StateNotifierProvider<EditorShortcutsController, EditorShortcutsState>(
        (ref) => EditorShortcutsController());

class EditorShortcutsController extends StateNotifier<EditorShortcutsState> {
  EditorShortcutsController() : super(const EditorShortcutsState()) {
    _initDefaults();
  }

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  void setFilterCategory(String? category) =>
      state = state.copyWith(filterCategory: category, clearFilter: category == null);

  /// Start editing a shortcut (the UI should capture the next key combo).
  void beginEdit(String bindingId) =>
      state = state.copyWith(editingId: bindingId);

  /// Assign new keys to the binding being edited.
  void assignKeys(String keys) {
    final id = state.editingId;
    if (id == null) return;
    state = state.copyWith(
      bindings: [
        for (final b in state.bindings)
          if (b.id == id && b.customizable) b.copyWith(keys: keys) else b,
      ],
      clearEditing: true,
    );
  }

  /// Cancel editing.
  void cancelEdit() => state = state.copyWith(clearEditing: true);

  /// Reset a single binding to its default.
  void resetBinding(String bindingId) {
    final defaults = _defaults();
    final def = defaults.cast<ShortcutBinding?>().firstWhere(
        (b) => b?.id == bindingId,
        orElse: () => null);
    if (def == null) return;
    state = state.copyWith(
      bindings: [
        for (final b in state.bindings)
          if (b.id == bindingId) def else b,
      ],
    );
  }

  /// Reset all bindings to defaults.
  void resetAll() {
    state = state.copyWith(bindings: _defaults());
  }

  void _initDefaults() {
    state = state.copyWith(bindings: _defaults());
  }

  static List<ShortcutBinding> _defaults() => const [
        // File
        ShortcutBinding(id: 's_open', action: 'open', label: 'Open file', category: 'File', keys: 'Ctrl+O'),
        ShortcutBinding(id: 's_save', action: 'save', label: 'Save / Export', category: 'File', keys: 'Ctrl+S'),
        ShortcutBinding(id: 's_print', action: 'print', label: 'Print', category: 'File', keys: 'Ctrl+P'),
        // Edit
        ShortcutBinding(id: 's_undo', action: 'undo', label: 'Undo', category: 'Edit', keys: 'Ctrl+Z'),
        ShortcutBinding(id: 's_redo', action: 'redo', label: 'Redo', category: 'Edit', keys: 'Ctrl+Shift+Z'),
        ShortcutBinding(id: 's_copy', action: 'copy', label: 'Copy', category: 'Edit', keys: 'Ctrl+C'),
        ShortcutBinding(id: 's_paste', action: 'paste', label: 'Paste', category: 'Edit', keys: 'Ctrl+V'),
        ShortcutBinding(id: 's_delete', action: 'delete', label: 'Delete', category: 'Edit', keys: 'Delete'),
        ShortcutBinding(id: 's_selall', action: 'select_all', label: 'Select all', category: 'Edit', keys: 'Ctrl+A'),
        // View
        ShortcutBinding(id: 's_zoomin', action: 'zoom_in', label: 'Zoom in', category: 'View', keys: 'Ctrl++'),
        ShortcutBinding(id: 's_zoomout', action: 'zoom_out', label: 'Zoom out', category: 'View', keys: 'Ctrl+-'),
        ShortcutBinding(id: 's_fitpage', action: 'fit_page', label: 'Fit page', category: 'View', keys: 'Ctrl+0'),
        // Navigation
        ShortcutBinding(id: 's_prevpage', action: 'prev_page', label: 'Previous page', category: 'Navigation', keys: 'PgUp'),
        ShortcutBinding(id: 's_nextpage', action: 'next_page', label: 'Next page', category: 'Navigation', keys: 'PgDn'),
        ShortcutBinding(id: 's_firstpage', action: 'first_page', label: 'First page', category: 'Navigation', keys: 'Home'),
        ShortcutBinding(id: 's_lastpage', action: 'last_page', label: 'Last page', category: 'Navigation', keys: 'End'),
        // Tools
        ShortcutBinding(id: 's_find', action: 'find', label: 'Find in document', category: 'Tools', keys: 'Ctrl+F'),
        ShortcutBinding(id: 's_draw', action: 'tool_draw', label: 'Drawing tool', category: 'Tools', keys: 'D'),
        ShortcutBinding(id: 's_text', action: 'tool_text', label: 'Text tool', category: 'Tools', keys: 'T'),
        ShortcutBinding(id: 's_highlight', action: 'tool_highlight', label: 'Highlighter', category: 'Tools', keys: 'H'),
        ShortcutBinding(id: 's_pan', action: 'tool_pan', label: 'Pan / Move', category: 'Tools', keys: 'V'),
        ShortcutBinding(id: 's_eraser', action: 'tool_eraser', label: 'Eraser', category: 'Tools', keys: 'E'),
      ];
}
