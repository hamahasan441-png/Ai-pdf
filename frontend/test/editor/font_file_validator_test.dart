import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/font_file_validator.dart';

void main() {
  const kurdish = <int>[0x0695, 0x06B5, 0x06CE, 0x06D5, 0x06C6, 0x06CA];

  test('HTML, JSON, OTF, and truncated bytes are not TrueType fonts', () {
    expect(validateTrueType(Uint8List.fromList('<html>404</html>'.codeUnits)).ok, isFalse);
    expect(validateTrueType(Uint8List.fromList('{"error":true}'.codeUnits)).ok, isFalse);
    final otto = Uint8List(12);
    otto[0] = 0x4F;
    otto[1] = 0x54;
    otto[2] = 0x54;
    otto[3] = 0x4F;
    expect(validateTrueType(otto).reason, contains('OTTO'));
    expect(validateTrueType(Uint8List(8)).ok, isFalse);
  });

  test('a measured cmap covers the Kurdish letters it contains and not Latin A', () {
    final font = _fontWithBmpRange(0x0695, 0x06D5);
    expect(validateTrueType(font).ok, isTrue);
    final covered = bmpCoverage(font, kurdish);
    expect(covered, isNotNull);
    expect(covered!.complete, isTrue);
    expect(covered.missing, isEmpty);

    final withLatin = bmpCoverage(font, [...kurdish, 0x41]);
    expect(withLatin!.complete, isFalse);
    expect(withLatin.missing, [0x41]);
  });

  test('coverage is null when the cmap cannot be read', () {
    expect(bmpCoverage(Uint8List.fromList('<html>'.codeUnits), kurdish), isNull);
    expect(bmpCoverage(_fontWithBmpRange(0x0695, 0x06D5), const []), isNull);
  });
}

Uint8List _fontWithBmpRange(int startCode, int endCode) {
  final cmap = _cmapFormat4(startCode, endCode);
  const tableOffset = 12 + 16;
  final out = Uint8List(tableOffset + cmap.length);
  final data = ByteData.sublistView(out);
  data.setUint32(0, 0x00010000);
  data.setUint16(4, 1);
  data.setUint16(6, 16);
  out[12] = 0x63;
  out[13] = 0x6D;
  out[14] = 0x61;
  out[15] = 0x70;
  data.setUint32(20, tableOffset);
  data.setUint32(24, cmap.length);
  out.setRange(tableOffset, tableOffset + cmap.length, cmap);
  return out;
}

Uint8List _cmapFormat4(int startCode, int endCode) {
  const segCount = 2;
  final bytes = Uint8List(12 + 16 + segCount * 8);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 0);
  data.setUint16(2, 1);
  data.setUint16(4, 3);
  data.setUint16(6, 1);
  data.setUint32(8, 12);
  const sub = 12;
  data.setUint16(sub, 4);
  data.setUint16(sub + 2, bytes.length - sub);
  data.setUint16(sub + 6, segCount * 2);
  data.setUint16(sub + 8, 4);
  data.setUint16(sub + 10, 1);
  const endAt = sub + 14;
  data.setUint16(endAt, endCode);
  data.setUint16(endAt + 2, 0xFFFF);
  const startAt = endAt + segCount * 2 + 2;
  data.setUint16(startAt, startCode);
  data.setUint16(startAt + 2, 0xFFFF);
  const deltaAt = startAt + segCount * 2;
  data.setUint16(deltaAt, 1);
  data.setUint16(deltaAt + 2, 1);
  return bytes;
}
