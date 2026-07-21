import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Document template service — pre-built and user-saved form layouts.
///
/// Templates are annotation layouts (field positions + labels) that can be
/// applied to any PDF. Use cases:
/// - "German Anmeldung form" template (pre-positioned fields)
/// - "Invoice" template (header, line items, total)
/// - User-saved: "my company letterhead" with logo + signature positions
///
/// Templates store ONLY the layout (positions, sizes, labels) — not the
/// filled values (those come from UserProfile or FormProfile).
class DocumentTemplateService {
  static const String _storageKey = 'doc_templates_v1';
  static const int _maxTemplates = 100;

  const DocumentTemplateService();

  /// Save a template.
  Future<void> saveTemplate(DocumentTemplate template) async {
    final prefs = await SharedPreferences.getInstance();
    final templates = await _loadAll(prefs);
    templates[template.id] = template;
    if (templates.length > _maxTemplates) {
      final sorted = templates.entries.toList()
        ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
      templates.remove(sorted.first.key);
    }
    await _saveAll(prefs, templates);
  }

  /// Load a template by ID.
  Future<DocumentTemplate?> loadTemplate(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final templates = await _loadAll(prefs);
    return templates[id];
  }

  /// List all saved templates.
  Future<List<DocumentTemplate>> listTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final templates = await _loadAll(prefs);
    final list = templates.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Delete a template.
  Future<void> deleteTemplate(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final templates = await _loadAll(prefs);
    templates.remove(id);
    await _saveAll(prefs, templates);
  }

  Future<Map<String, DocumentTemplate>> _loadAll(SharedPreferences prefs) async {
    final raw = prefs.getString(_storageKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, DocumentTemplate.fromJson(v)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAll(SharedPreferences prefs, Map<String, DocumentTemplate> templates) async {
    await prefs.setString(_storageKey, jsonEncode(
      templates.map((k, v) => MapEntry(k, v.toJson())),
    ));
  }
}

/// A saved document template (layout without values).
class DocumentTemplate {
  final String id;
  final String name;
  final String category; // e.g. "German forms", "Invoices", "Contracts"
  final List<TemplateField> fields;
  final DateTime createdAt;

  DocumentTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.fields,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'fields': fields.map((f) => f.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory DocumentTemplate.fromJson(dynamic j) {
    final map = j as Map<String, dynamic>;
    return DocumentTemplate(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? '',
      fields: (map['fields'] as List<dynamic>?)
              ?.map((f) => TemplateField.fromJson(f))
              .toList() ??
          [],
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? ''),
    );
  }
}

/// A field in a template (position + label + type, no value).
class TemplateField {
  final double x, y, w, h; // normalised 0..1
  final String label;
  final String fieldType; // text, date, checkbox, radio, signature, etc.
  final int page;

  const TemplateField({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.label,
    required this.fieldType,
    this.page = 0,
  });

  Map<String, dynamic> toJson() => {
        'x': x, 'y': y, 'w': w, 'h': h,
        'label': label, 'fieldType': fieldType, 'page': page,
      };

  factory TemplateField.fromJson(dynamic j) {
    final map = j as Map<String, dynamic>;
    return TemplateField(
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      w: (map['w'] as num?)?.toDouble() ?? 0,
      h: (map['h'] as num?)?.toDouble() ?? 0,
      label: map['label'] as String? ?? '',
      fieldType: map['fieldType'] as String? ?? 'text',
      page: map['page'] as int? ?? 0,
    );
  }
}
