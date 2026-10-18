import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/security/data/pdf_encryptor.dart';

/// Encrypted copies of the export fixtures for tool/verify_preserving_export.py
/// (run with PDOCZY_EXPORT_OUT set; CI does).
void main() {
  final outDir = Platform.environment['PDOCZY_EXPORT_OUT'];
  final expectations = <Map<String, Object?>>[];

  Uint8List fixture(String name) => File('test/fixtures/pdf/$name.pdf').readAsBytesSync();

  bool contains(Uint8List hay, String needle) => latin1.decode(hay).contains(needle);

  tearDownAll(() {
    if (outDir == null) return;
    // Its own file: test files run in parallel (the verifier reads all).
    File('$outDir/expectations_encryption.json').writeAsStringSync(jsonEncode(expectations));
  });

  void keep(String name, Uint8List bytes, Map<String, Object?> expect) {
    if (outDir == null) return;
    File('$outDir/$name.pdf').writeAsBytesSync(bytes);
    expectations.add({'file': '$name.pdf', ...expect});
  }

  test('nothing readable is left in the file', () {
    final src = fixture('rich_classic');
    expect(contains(src, 'Pdoczy Fixture'), isTrue, reason: 'the fixture title is plain text');
    final out = PdfEncryptor().encrypt(src, userPassword: 'kurd-2026');
    expect(contains(out, 'Pdoczy Fixture'), isFalse);
    expect(contains(out, 'ORIGINAL-SEARCHABLE-TEXT'), isFalse);
    expect(contains(out, 'example.com'), isFalse, reason: 'link URIs are strings too');
    expect(contains(out, '/Encrypt'), isTrue);
    expect(() => PdfObjectStore.parse(out), throwsA(isA<PdfSourceException>()),
        reason: 'our own parser sees an encrypted file');
    keep('encrypted_rich', out, {
      'password': 'kurd-2026',
      'encryption': 'AESv3',
      'pages': [
        {'text_contains': ['ORIGINAL-SEARCHABLE-TEXT'], 'links': 1, 'widgets': 1},
        {'text_contains': ['ORIGINAL-SEARCHABLE-TEXT']},
        {'text_contains': ['ORIGINAL-SEARCHABLE-TEXT'], 'links': 1},
      ],
      'toc_entries': 3,
      'title': 'Pdoczy Fixture',
    });
  });

  test('object streams, images and forms survive; a Unicode password works', () {
    final images = PdfEncryptor().encrypt(fixture('images'), userPassword: 'سڵاو', ownerPassword: 'owner');
    keep('encrypted_images', images, {
      'password': 'سڵاو',
      'pages': [
        {'text_contains': ['ORIGINAL-SEARCHABLE-TEXT'], 'images': 3, 'size': [400, 300]},
        {'images': 0, 'size': [200, 500]},
      ],
    });
    final objstm = PdfEncryptor().encrypt(fixture('rich_objstm'), userPassword: 'x');
    keep('encrypted_objstm', objstm, {
      'password': 'x',
      'pages': [
        {'text_contains': ['ORIGINAL-SEARCHABLE-TEXT']},
        {},
        {},
      ],
    });
    final forms = PdfEncryptor().encrypt(fixture('forms'), userPassword: 'p');
    keep('encrypted_forms', forms, {
      'password': 'p',
      'pages': [
        {'widgets': 9},
        {'widgets': 1, 'rotation': 90},
      ],
      'fields': {'name': 'Ada', 'size': 'M', 'id': 'ID-7'},
    });
  });

  test('an already encrypted file and an empty password are refused', () {
    expect(() => PdfEncryptor().encrypt(fixture('encrypted'), userPassword: 'a'), throwsA(isA<PdfSourceException>()));
    expect(() => PdfEncryptor().encrypt(fixture('rich_classic'), userPassword: ''), throwsArgumentError);
  });

  test('two encryptions of one file differ (random key and IVs)', () {
    final a = PdfEncryptor().encrypt(fixture('inherited'), userPassword: 'a');
    final b = PdfEncryptor().encrypt(fixture('inherited'), userPassword: 'a');
    expect(a, isNot(equals(b)));
    final seeded = PdfEncryptor(random: Random(1)).encrypt(fixture('inherited'), userPassword: 'a');
    expect(PdfEncryptor(random: Random(1)).encrypt(fixture('inherited'), userPassword: 'a'), seeded);
  });

  test('permission bits', () {
    expect(const PdfAccess().pValue, -4);
    expect(const PdfAccess(print: false, copy: false, modify: false, annotate: false).pValue, -3904);
  });
}
