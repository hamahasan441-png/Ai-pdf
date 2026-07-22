import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';

/// Outcome of validating a single field value (Phase 14).
class FieldValidationResult {
  final bool valid;

  /// Human-readable reason the value is invalid (empty when [valid]).
  final String error;

  /// An optional corrected value the UI can offer as a one-tap fix.
  final String? suggestion;

  const FieldValidationResult({
    required this.valid,
    this.error = '',
    this.suggestion,
  });

  static const ok = FieldValidationResult(valid: true);
}

/// On-device form-field validation, mirroring the backend `FieldValidator`.
///
/// Runs entirely on the client so the smart-fill review sheet can flag bad
/// values (invalid email, wrong date format, bad IBAN checksum, missing
/// required field) BEFORE anything is placed on the page — no network round
/// trip, works offline, and keeps the "AI proposes, user reviews" contract.
///
/// Rules are intentionally kept in sync with
/// `backend/app/services/ai/field_validator.py` so the offline and managed
/// paths agree. Pure Dart, no Flutter dependency → fully unit-testable.
class FieldValidationService {
  const FieldValidationService();

  /// Validate [value] against a [FormFieldKind].
  ///
  /// When [required] is true, an empty value fails. Otherwise an empty value is
  /// considered valid (the "is it well-formed" check is separate from the
  /// "is it present" check).
  FieldValidationResult validate(
    String value,
    FormFieldKind kind, {
    bool required = false,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return required
          ? const FieldValidationResult(
              valid: false, error: 'This field is required')
          : FieldValidationResult.ok;
    }

    switch (kind) {
      case FormFieldKind.email:
        return _email(trimmed);
      case FormFieldKind.phone:
        return _phone(trimmed);
      case FormFieldKind.date:
        return _date(trimmed);
      case FormFieldKind.number:
        return _number(trimmed);
      case FormFieldKind.name:
        return _name(trimmed);
      case FormFieldKind.checkbox:
      case FormFieldKind.radio:
      case FormFieldKind.combobox:
      case FormFieldKind.signature:
      case FormFieldKind.text:
        return FieldValidationResult.ok;
    }
  }

  /// Validate a named-type string (`email`/`phone`/`date`/`number`/`iban`/
  /// `zip`/`name`/`text`) — matches the backend's string contract for callers
  /// that don't have a [FormFieldKind] on hand.
  FieldValidationResult validateType(
    String value,
    String type, {
    bool required = false,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return required
          ? const FieldValidationResult(
              valid: false, error: 'This field is required')
          : FieldValidationResult.ok;
    }
    switch (type.toLowerCase()) {
      case 'email':
        return _email(trimmed);
      case 'phone':
        return _phone(trimmed);
      case 'date':
        return _date(trimmed);
      case 'number':
        return _number(trimmed);
      case 'iban':
        return _iban(trimmed);
      case 'zip':
        return _zip(trimmed);
      case 'name':
        return _name(trimmed);
      default:
        return FieldValidationResult.ok;
    }
  }

  // --- individual validators (parity with the backend) ---------------------

  static final RegExp _emailRe =
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

  FieldValidationResult _email(String v) {
    if (_emailRe.hasMatch(v)) return FieldValidationResult.ok;
    if (!v.contains('@') && v.contains(' at ')) {
      return FieldValidationResult(
        valid: false,
        error: 'Missing @ symbol',
        suggestion: v.replaceAll(' at ', '@'),
      );
    }
    return const FieldValidationResult(
        valid: false, error: 'Invalid email format');
  }

  FieldValidationResult _phone(String v) {
    final digits = v.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.length >= 7 && digits.length <= 16) {
      return FieldValidationResult.ok;
    }
    return FieldValidationResult(
      valid: false,
      error: digits.length < 7 ? 'Phone number too short' : 'Phone number too long',
    );
  }

  static final List<RegExp> _dateRes = [
    RegExp(r'^\d{2}\.\d{2}\.\d{4}$'), // DD.MM.YYYY
    RegExp(r'^\d{2}/\d{2}/\d{4}$'), // DD/MM/YYYY
    RegExp(r'^\d{4}-\d{2}-\d{2}$'), // YYYY-MM-DD
    RegExp(r'^\d{2}-\d{2}-\d{4}$'), // DD-MM-YYYY
    RegExp(r'^\d{1,2}\.\d{1,2}\.\d{2,4}$'), // D.M.YY
  ];

  FieldValidationResult _date(String v) {
    for (final re in _dateRes) {
      if (re.hasMatch(v)) return FieldValidationResult.ok;
    }
    return const FieldValidationResult(
      valid: false,
      error: 'Unrecognized date format',
      suggestion: 'Use DD.MM.YYYY',
    );
  }

  FieldValidationResult _number(String v) {
    // Allow comma/dot decimals and spaces as thousands separators.
    final cleaned = v.replaceAll(' ', '').replaceAll('.', '').replaceAll(',', '.');
    if (double.tryParse(cleaned) != null) return FieldValidationResult.ok;
    return const FieldValidationResult(valid: false, error: 'Not a valid number');
  }

  FieldValidationResult _iban(String v) {
    final iban = v.replaceAll(' ', '').toUpperCase();
    if (iban.length < 15 || iban.length > 34) {
      return const FieldValidationResult(valid: false, error: 'IBAN length invalid');
    }
    if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]+$').hasMatch(iban)) {
      return const FieldValidationResult(valid: false, error: 'IBAN format invalid');
    }
    if (_ibanMod97(iban) != 1) {
      return const FieldValidationResult(valid: false, error: 'IBAN checksum invalid');
    }
    return FieldValidationResult.ok;
  }

  /// Mod-97 over the rearranged IBAN, computed digit-by-digit to avoid big-int
  /// overflow (IBANs can be up to 34 chars → far beyond a 64-bit int).
  int _ibanMod97(String iban) {
    final rearranged = iban.substring(4) + iban.substring(0, 4);
    final buf = StringBuffer();
    for (final code in rearranged.codeUnits) {
      if (code >= 0x41 && code <= 0x5A) {
        buf.write(code - 55); // A=10 ... Z=35
      } else {
        buf.write(String.fromCharCode(code));
      }
    }
    final numeric = buf.toString();
    var remainder = 0;
    for (var i = 0; i < numeric.length; i++) {
      remainder = (remainder * 10 + (numeric.codeUnitAt(i) - 0x30)) % 97;
    }
    return remainder;
  }

  FieldValidationResult _zip(String v) {
    if (RegExp(r'^\d{5}$').hasMatch(v)) return FieldValidationResult.ok; // German PLZ
    if (RegExp(r'^[A-Z0-9]{3,10}$').hasMatch(v.toUpperCase().replaceAll(' ', ''))) {
      return FieldValidationResult.ok; // generic
    }
    return const FieldValidationResult(
        valid: false, error: 'Invalid postal code format');
  }

  FieldValidationResult _name(String v) {
    if (v.length < 2) {
      return const FieldValidationResult(valid: false, error: 'Name too short');
    }
    if (v.runes.any((r) => r >= 0x30 && r <= 0x39)) {
      return const FieldValidationResult(
          valid: false, error: 'Name should not contain digits');
    }
    return FieldValidationResult.ok;
  }
}
