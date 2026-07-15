import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the user's personal details ON-DEVICE (encrypted) so the AI form
/// filler can pre-answer known fields instantly, without asking every time.
///
/// This contains PII (name, DOB, passport…), so it is kept in
/// flutter_secure_storage — never uploaded, never in the repo. It works fully
/// offline / in guest mode (no backend account needed).
class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  static const _key = 'user_profile_v1';

  /// Canonical fields shown in the Profile screen: (key, label, icon-less).
  /// Kept here so the AI prompt block uses friendly labels.
  static const List<(String, String)> fields = [
    ('first_name', 'First Name'),
    ('last_name', 'Last Name'),
    ('date_of_birth', 'Date of Birth'),
    ('nationality', 'Nationality'),
    ('phone_number', 'Phone'),
    ('email', 'Email'),
    ('street_address', 'Address'),
    ('city', 'City'),
    ('postal_code', 'Postal Code'),
    ('country', 'Country'),
    ('id_number', 'ID / Passport No.'),
    ('employer_name', 'Employer'),
    ('job_title', 'Job Title'),
  ];

  final _secure = const FlutterSecureStorage();
  final ValueNotifier<Map<String, String>> notifier =
      ValueNotifier<Map<String, String>>({});
  bool _loaded = false;

  Map<String, String> get data => notifier.value;
  bool get hasData => notifier.value.values.any((v) => v.trim().isNotEmpty);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await _secure.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          notifier.value =
              decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
        }
      }
    } catch (_) {
      notifier.value = {};
    }
    _loaded = true;
  }

  Future<void> save(Map<String, String> values) async {
    final cleaned = <String, String>{};
    values.forEach((k, v) {
      if (v.trim().isNotEmpty) cleaned[k] = v.trim();
    });
    notifier.value = cleaned;
    try {
      await _secure.write(key: _key, value: jsonEncode(cleaned));
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<void> clear() async {
    notifier.value = {};
    try {
      await _secure.delete(key: _key);
    } catch (_) {}
  }

  /// A compact block the AI can use to pre-fill matching fields.
  /// Returns '' when no data is saved.
  String asPromptBlock() {
    final d = notifier.value;
    if (d.isEmpty) return '';
    final labelFor = {for (final f in fields) f.$1: f.$2};
    final lines = <String>[];
    d.forEach((k, v) {
      if (v.trim().isEmpty) return;
      final label = labelFor[k] ?? k.replaceAll('_', ' ');
      lines.add('- $label: $v');
    });
    return lines.join('\n');
  }
}
