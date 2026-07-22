import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/text_transform_service.dart';

void main() {
  const svc = TextTransformService();

  group('TextTransformService (Phase 25)', () {
    test('upper / lower', () {
      expect(svc.upper('Hello'), 'HELLO');
      expect(svc.lower('Hello'), 'hello');
    });

    test('titleCase capitalises each word, lower-cases the rest', () {
      expect(svc.titleCase('hello world'), 'Hello World');
      expect(svc.titleCase('the QUICK brown'), 'The Quick Brown');
    });

    test('titleCase preserves the original spacing', () {
      expect(svc.titleCase('a  b'), 'A  B');
    });

    test('sentenceCase capitalises the first letter of each sentence', () {
      expect(
        svc.sentenceCase('hello world. how ARE you? fine.'),
        'Hello world. How are you? Fine.',
      );
    });

    test('toggleCase swaps case per letter', () {
      expect(svc.toggleCase('Hello World'), 'hELLO wORLD');
      expect(svc.toggleCase('aB3c'), 'Ab3C');
    });

    test('normalizeWhitespace trims and collapses runs', () {
      expect(svc.normalizeWhitespace('  a\t\tb\n c  '), 'a b c');
      expect(svc.normalizeWhitespace('single'), 'single');
    });

    group('smartQuotes', () {
      test('double quotes become opening/closing', () {
        expect(svc.smartQuotes('"hi"'), '\u201Chi\u201D');
        expect(svc.smartQuotes('say "yes" now'), 'say \u201Cyes\u201D now');
      });

      test('apostrophe inside a word becomes a right single quote', () {
        expect(svc.smartQuotes("it's"), 'it\u2019s');
      });

      test('single quotes around a word open and close', () {
        expect(svc.smartQuotes("'quote'"), '\u2018quote\u2019');
      });

      test('leaves text without quotes untouched', () {
        expect(svc.smartQuotes('no quotes here'), 'no quotes here');
      });
    });
  });
}
