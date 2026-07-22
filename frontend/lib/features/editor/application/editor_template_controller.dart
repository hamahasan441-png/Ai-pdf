import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A reusable annotation preset/template (Phase 35).
///
/// Stores the configuration for a stamp, text box, shape, or any annotation
/// the user wants to reuse across documents — without storing actual position
/// (applied at the cursor point).
class AnnotationTemplate {
  final String id;
  final String name;
  final String category;
  final TemplateKind kind;
  final Map<String, dynamic> properties;
  final DateTime createdAt;
  final bool builtIn;

  const AnnotationTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.kind,
    required this.properties,
    required this.createdAt,
    this.builtIn = false,
  });

  AnnotationTemplate copyWith({String? name, String? category}) =>
      AnnotationTemplate(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        kind: kind,
        properties: properties,
        createdAt: createdAt,
        builtIn: builtIn,
      );
}

enum TemplateKind { text, stamp, shape, image, composite }

/// UI state for the template/presets feature (Phase 35).
class EditorTemplateState {
  final bool visible;
  final List<AnnotationTemplate> templates;
  final String? selectedCategory;
  final TemplateKind? filterKind;

  const EditorTemplateState({
    this.visible = false,
    this.templates = const [],
    this.selectedCategory,
    this.filterKind,
  });

  List<String> get categories => [
        ...{for (final t in templates) t.category},
      ]..sort();

  List<AnnotationTemplate> get filtered {
    var list = templates;
    if (selectedCategory != null) {
      list = list.where((t) => t.category == selectedCategory).toList();
    }
    if (filterKind != null) {
      list = list.where((t) => t.kind == filterKind).toList();
    }
    return list;
  }

  bool get hasTemplates => templates.isNotEmpty;

  EditorTemplateState copyWith({
    bool? visible,
    List<AnnotationTemplate>? templates,
    String? selectedCategory,
    TemplateKind? filterKind,
    bool clearCategory = false,
    bool clearKind = false,
  }) =>
      EditorTemplateState(
        visible: visible ?? this.visible,
        templates: templates ?? this.templates,
        selectedCategory:
            clearCategory ? null : (selectedCategory ?? this.selectedCategory),
        filterKind: clearKind ? null : (filterKind ?? this.filterKind),
      );
}

/// Controller for the annotation templates/presets panel (Phase 35).
///
/// Manages a library of reusable annotation presets: save the current
/// annotation as a template, browse/filter/search, apply to the cursor point.
/// Templates are persisted via SharedPreferences (serialized as JSON maps).
final editorTemplateProvider =
    StateNotifierProvider<EditorTemplateController, EditorTemplateState>(
        (ref) => EditorTemplateController());

class EditorTemplateController extends StateNotifier<EditorTemplateState> {
  EditorTemplateController() : super(const EditorTemplateState()) {
    _loadBuiltIns();
  }

  int _nextId = 1;

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  void setCategory(String? category) =>
      state = state.copyWith(selectedCategory: category, clearCategory: category == null);

  void setKindFilter(TemplateKind? kind) =>
      state = state.copyWith(filterKind: kind, clearKind: kind == null);

  /// Save a new user template.
  AnnotationTemplate save({
    required String name,
    required String category,
    required TemplateKind kind,
    required Map<String, dynamic> properties,
  }) {
    final template = AnnotationTemplate(
      id: 'tpl_${_nextId++}',
      name: name,
      category: category,
      kind: kind,
      properties: properties,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(templates: [...state.templates, template]);
    return template;
  }

  /// Rename/re-categorize an existing template.
  void update(String id, {String? name, String? category}) {
    state = state.copyWith(
      templates: [
        for (final t in state.templates)
          if (t.id == id) t.copyWith(name: name, category: category) else t,
      ],
    );
  }

  /// Delete a user template (built-ins can't be deleted).
  void delete(String id) {
    state = state.copyWith(
      templates: [
        for (final t in state.templates)
          if (t.id != id || t.builtIn) t,
      ],
    );
  }

  /// Load templates from external data (e.g. SharedPreferences on app start).
  void loadAll(List<AnnotationTemplate> templates) {
    state = state.copyWith(
      templates: [...state.templates.where((t) => t.builtIn), ...templates],
    );
  }

  void _loadBuiltIns() {
    final builtIns = [
      AnnotationTemplate(
        id: 'builtin_approved',
        name: 'APPROVED',
        category: 'Stamps',
        kind: TemplateKind.stamp,
        properties: const {'text': 'APPROVED', 'color': 0xFF4CAF50},
        createdAt: DateTime(2024),
        builtIn: true,
      ),
      AnnotationTemplate(
        id: 'builtin_draft',
        name: 'DRAFT',
        category: 'Stamps',
        kind: TemplateKind.stamp,
        properties: const {'text': 'DRAFT', 'color': 0xFFFF9800},
        createdAt: DateTime(2024),
        builtIn: true,
      ),
      AnnotationTemplate(
        id: 'builtin_confidential',
        name: 'CONFIDENTIAL',
        category: 'Stamps',
        kind: TemplateKind.stamp,
        properties: const {'text': 'CONFIDENTIAL', 'color': 0xFFF44336},
        createdAt: DateTime(2024),
        builtIn: true,
      ),
      AnnotationTemplate(
        id: 'builtin_signature_line',
        name: 'Signature Line',
        category: 'Forms',
        kind: TemplateKind.composite,
        properties: const {'type': 'signature_line', 'label': 'Signature'},
        createdAt: DateTime(2024),
        builtIn: true,
      ),
      AnnotationTemplate(
        id: 'builtin_date_field',
        name: 'Date Field',
        category: 'Forms',
        kind: TemplateKind.text,
        properties: const {'placeholder': 'DD.MM.YYYY', 'color': 0xFF2196F3},
        createdAt: DateTime(2024),
        builtIn: true,
      ),
    ];
    state = state.copyWith(templates: [...builtIns, ...state.templates]);
  }
}
