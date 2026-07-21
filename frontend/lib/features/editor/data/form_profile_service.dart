import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Reusable form profiles — save and recall field-value sets per form type.
///
/// When a user fills a specific form type (e.g. "Anmeldeformular", "Mietvertrag"),
/// this service saves the filled values as a named profile. Next time the same
/// form type is detected, the values are auto-suggested from the saved profile
/// (in addition to the personal profile).
///
/// ### How it differs from UserProfileService
/// - UserProfileService: personal data (name, address, DOB) — universal across all forms.
/// - FormProfileService: form-specific answers (e.g. "reason for application",
///   "desired move-in date") — relevant only to that form type.
///
/// ### Storage
/// Persisted in SharedPreferences as JSON. Keyed by a normalized form-type label.
class FormProfileService {
  static const String _storageKey = 'form_profiles_v1';
  static const int _maxProfiles = 50;

  const FormProfileService();

  /// Save a form profile (field values for a form type).
  Future<void> saveProfile({
    required String formType,
    required Map<String, String> fieldValues,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = _loadAll(prefs);
    profiles[_normalize(formType)] = FormProfile(
      formType: formType,
      fieldValues: fieldValues,
      savedAt: DateTime.now(),
    );
    // Evict oldest if over cap.
    if (profiles.length > _maxProfiles) {
      final sorted = profiles.entries.toList()
        ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
      profiles.remove(sorted.first.key);
    }
    await prefs.setString(_storageKey, jsonEncode(
      profiles.map((k, v) => MapEntry(k, v.toJson())),
    ));
  }

  /// Load saved field values for a form type. Returns empty map if none saved.
  Future<Map<String, String>> loadProfile(String formType) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = _loadAll(prefs);
    return profiles[_normalize(formType)]?.fieldValues ?? {};
  }

  /// List all saved form profile types.
  Future<List<String>> listProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = _loadAll(prefs);
    return profiles.values.map((p) => p.formType).toList();
  }

  /// Delete a saved form profile.
  Future<void> deleteProfile(String formType) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = _loadAll(prefs);
    profiles.remove(_normalize(formType));
    await prefs.setString(_storageKey, jsonEncode(
      profiles.map((k, v) => MapEntry(k, v.toJson())),
    ));
  }

  /// Check if a profile exists for a form type.
  Future<bool> hasProfile(String formType) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = _loadAll(prefs);
    return profiles.containsKey(_normalize(formType));
  }

  Map<String, FormProfile> _loadAll(SharedPreferences prefs) {
    final raw = prefs.getString(_storageKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, FormProfile.fromJson(v)));
    } catch (_) {
      return {};
    }
  }

  String _normalize(String formType) => formType.trim().toLowerCase();
}

/// A saved set of field values for a specific form type.
class FormProfile {
  final String formType;
  final Map<String, String> fieldValues;
  final DateTime savedAt;

  FormProfile({
    required this.formType,
    required this.fieldValues,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'formType': formType,
        'fieldValues': fieldValues,
        'savedAt': savedAt.toIso8601String(),
      };

  factory FormProfile.fromJson(dynamic j) {
    final map = j as Map<String, dynamic>;
    return FormProfile(
      formType: map['formType'] as String? ?? '',
      fieldValues: (map['fieldValues'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
      savedAt: DateTime.tryParse(map['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
