/// Cross-field logic service — computes dependent field values.
///
/// In real forms, some fields depend on others:
/// - Total = sum of line items
/// - Age = computed from date of birth
/// - Full name = first name + " " + last name
/// - BMI = weight / (height²)
/// - Net amount = gross - tax
///
/// This service detects and applies these relationships automatically
/// when form values change.
class CrossFieldLogicService {
  const CrossFieldLogicService();

  /// Apply cross-field computations to a set of field values.
  /// Returns any computed values that should be auto-filled.
  Map<String, String> computeDependents(Map<String, String> fieldValues) {
    final computed = <String, String>{};

    // Full name from first + last
    _computeFullName(fieldValues, computed);
    // Age from date of birth
    _computeAge(fieldValues, computed);
    // Net/gross/tax relationships
    _computeFinancial(fieldValues, computed);

    return computed;
  }

  /// Check if a field is computable from other fields.
  bool isComputable(String fieldLabel, Map<String, String> availableFields) {
    final lower = fieldLabel.toLowerCase();
    if (_isFullNameField(lower) && _hasNameParts(availableFields)) return true;
    if (_isAgeField(lower) && _hasDob(availableFields)) return true;
    if (_isNetField(lower) && _hasGrossAndTax(availableFields)) return true;
    return false;
  }

  void _computeFullName(Map<String, String> fields, Map<String, String> computed) {
    final first = _findValue(fields, ['first_name', 'vorname', 'prénom', 'nombre']);
    final last = _findValue(fields, ['last_name', 'nachname', 'nom', 'apellido']);
    if (first != null && last != null) {
      computed['full_name'] = '$first $last';
      computed['name'] = '$first $last';
    }
  }

  void _computeAge(Map<String, String> fields, Map<String, String> computed) {
    final dob = _findValue(fields, ['date_of_birth', 'geburtsdatum', 'dob']);
    if (dob == null) return;
    final birthDate = _parseDate(dob);
    if (birthDate == null) return;
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    if (age > 0 && age < 150) {
      computed['age'] = age.toString();
      computed['alter'] = age.toString();
    }
  }

  void _computeFinancial(Map<String, String> fields, Map<String, String> computed) {
    final gross = _findNumeric(fields, ['gross', 'brutto', 'total']);
    final tax = _findNumeric(fields, ['tax', 'steuer', 'mwst', 'vat']);
    if (gross != null && tax != null) {
      computed['net'] = (gross - tax).toStringAsFixed(2);
      computed['netto'] = (gross - tax).toStringAsFixed(2);
    } else if (gross != null && tax == null) {
      // Assume 19% VAT (Germany) if no tax provided
      final vatAmount = gross * 0.19;
      computed['tax'] = vatAmount.toStringAsFixed(2);
      computed['net'] = (gross - vatAmount).toStringAsFixed(2);
    }
  }

  String? _findValue(Map<String, String> fields, List<String> keys) {
    for (final key in keys) {
      for (final entry in fields.entries) {
        if (entry.key.toLowerCase().contains(key) && entry.value.isNotEmpty) {
          return entry.value;
        }
      }
    }
    return null;
  }

  double? _findNumeric(Map<String, String> fields, List<String> keys) {
    final val = _findValue(fields, keys);
    if (val == null) return null;
    return double.tryParse(val.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), ''));
  }

  DateTime? _parseDate(String s) {
    // Try common formats: DD.MM.YYYY, YYYY-MM-DD, DD/MM/YYYY
    final patterns = [
      RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$'), // DD.MM.YYYY
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$'),   // YYYY-MM-DD
      RegExp(r'^(\d{2})/(\d{2})/(\d{4})$'),   // DD/MM/YYYY
    ];
    for (final p in patterns) {
      final m = p.firstMatch(s);
      if (m == null) continue;
      try {
        if (s.contains('-') && s.indexOf('-') == 4) {
          return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
        }
        return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
      } catch (_) {}
    }
    return null;
  }

  bool _isFullNameField(String l) => l.contains('full') && l.contains('name') || l == 'name' || l == 'vollständiger name';
  bool _hasNameParts(Map<String, String> f) => _findValue(f, ['first_name', 'vorname']) != null && _findValue(f, ['last_name', 'nachname']) != null;
  bool _isAgeField(String l) => l == 'age' || l == 'alter' || l.contains('lebensalter');
  bool _hasDob(Map<String, String> f) => _findValue(f, ['date_of_birth', 'geburtsdatum']) != null;
  bool _isNetField(String l) => l.contains('net') || l.contains('netto');
  bool _hasGrossAndTax(Map<String, String> f) => _findNumeric(f, ['gross', 'brutto', 'total']) != null;
}
