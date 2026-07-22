import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/field_validation_service.dart';

void main() {
  const svc = FieldValidationService();

  group('FieldValidationService (Phase 14)', () {
    test('empty value is valid unless required', () {
      expect(svc.validate('', FormFieldKind.email).valid, isTrue);
      final req = svc.validate('  ', FormFieldKind.email, required: true);
      expect(req.valid, isFalse);
      expect(req.error, contains('required'));
    });

    test('email validation', () {
      expect(svc.validate('a@b.com', FormFieldKind.email).valid, isTrue);
      expect(svc.validate('not-an-email', FormFieldKind.email).valid, isFalse);
    });

    test('email " at " typo yields a suggestion', () {
      final r = svc.validate('john at example.com', FormFieldKind.email);
      expect(r.valid, isFalse);
      expect(r.suggestion, 'john@example.com');
    });

    test('phone length bounds', () {
      expect(svc.validate('+49 170 1234567', FormFieldKind.phone).valid, isTrue);
      expect(svc.validate('123', FormFieldKind.phone).valid, isFalse);
      expect(svc.validate('12345678901234567', FormFieldKind.phone).valid, isFalse);
    });

    test('date accepts common formats, rejects junk with a suggestion', () {
      expect(svc.validate('31.12.2026', FormFieldKind.date).valid, isTrue);
      expect(svc.validate('2026-12-31', FormFieldKind.date).valid, isTrue);
      final bad = svc.validate('Dec 31', FormFieldKind.date);
      expect(bad.valid, isFalse);
      expect(bad.suggestion, 'Use DD.MM.YYYY');
    });

    test('number allows european separators', () {
      expect(svc.validate('1.234,56', FormFieldKind.number).valid, isTrue);
      expect(svc.validate('abc', FormFieldKind.number).valid, isFalse);
    });

    test('name rejects digits and too-short values', () {
      expect(svc.validate('Ada Lovelace', FormFieldKind.name).valid, isTrue);
      expect(svc.validate('A', FormFieldKind.name).valid, isFalse);
      expect(svc.validate('Agent007', FormFieldKind.name).valid, isFalse);
    });

    test('checkbox / text kinds are always well-formed', () {
      expect(svc.validate('anything', FormFieldKind.checkbox).valid, isTrue);
      expect(svc.validate('free text', FormFieldKind.text).valid, isTrue);
    });

    group('validateType (string contract, IBAN + zip)', () {
      test('valid German IBAN passes mod-97', () {
        final r = svc.validateType('DE89 3704 0044 0532 0130 00', 'iban');
        expect(r.valid, isTrue);
      });

      test('IBAN with a broken checksum fails', () {
        final r = svc.validateType('DE89 3704 0044 0532 0130 01', 'iban');
        expect(r.valid, isFalse);
        expect(r.error, contains('checksum'));
      });

      test('IBAN wrong length / format', () {
        expect(svc.validateType('DE00', 'iban').valid, isFalse);
      });

      test('zip accepts 5-digit PLZ and generic alphanumerics', () {
        expect(svc.validateType('10115', 'zip').valid, isTrue);
        expect(svc.validateType('SW1A 1AA', 'zip').valid, isTrue);
        expect(svc.validateType('!!', 'zip').valid, isFalse);
      });

      test('unknown type is treated as free text', () {
        expect(svc.validateType('whatever', 'text').valid, isTrue);
      });
    });
  });
}
