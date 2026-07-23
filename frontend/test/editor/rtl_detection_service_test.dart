import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/rtl_detection_service.dart';

/// Tests for [RtlDetectionService], the direction detector the text renderer
/// (`annotation_draw`) and the vector exporter (`editor_export_service` /
/// `rtl_text_renderer`) use to auto-set direction when a text annotation has
/// no explicit [TextDirection] override.
void main() {
  const svc = RtlDetectionService();

  group('RtlDetectionService.isRtl (first-strong rule)', () {
    test('pure LTR / RTL scripts', () {
      expect(svc.isRtl('Hello'), isFalse);
      expect(svc.isRtl('مرحبا'), isTrue); // Arabic
      expect(svc.isRtl('سڵاو'), isTrue); // Kurdish (Arabic script)
      expect(svc.isRtl('שלום'), isTrue); // Hebrew
    });

    test('direction follows the FIRST strong character, not mere presence', () {
      // Starts with a Latin letter → LTR, even though it contains Arabic.
      expect(svc.isRtl('Hello مرحبا'), isFalse);
      // Starts with an Arabic letter → RTL, even though it contains Latin.
      expect(svc.isRtl('مرحبا Hello'), isTrue);
    });

    test('leading neutral characters (digits/punct/space) are skipped', () {
      expect(svc.isRtl('123 مرحبا'), isTrue);
      expect(svc.isRtl('  #@! مرحبا'), isTrue);
      expect(svc.isRtl('123 Hello'), isFalse);
    });

    test('no strong character defaults to LTR', () {
      expect(svc.isRtl(''), isFalse);
      expect(svc.isRtl('123 !!!'), isFalse);
      // Greek/Cyrillic are not classified as strong here → default LTR.
      expect(svc.isRtl('Ελληνικά'), isFalse);
      expect(svc.isRtl('Привет'), isFalse);
    });

    test('accented Latin-1 letters count as strong LTR', () {
      expect(svc.isRtl('Élan'), isFalse);
      expect(svc.isRtl('ñandú'), isFalse);
    });

    test('boundary code points', () {
      expect(svc.isRtl(String.fromCharCode(0x05D0)), isTrue); // Hebrew alef
      expect(svc.isRtl(String.fromCharCode(0xFB50)), isTrue); // Arabic PF-A start
    });
  });

  group('RtlDetectionService.isMajorityRtl', () {
    test('counts strong chars by direction', () {
      expect(svc.isMajorityRtl('مرحبا'), isTrue); // 5 RTL, 0 LTR
      expect(svc.isMajorityRtl('Hello'), isFalse); // 0 RTL, 5 LTR
      expect(svc.isMajorityRtl('مرحبا Hi'), isTrue); // 5 RTL > 2 LTR
      expect(svc.isMajorityRtl('Hello world مرحبا'), isFalse); // 10 LTR > 5 RTL
    });

    test('differs from isRtl on a balanced, RTL-led string', () {
      // "مرحبا Hello": 5 RTL vs 5 LTR → not a strict majority (5 > 5 is false),
      // yet the first strong char is RTL.
      expect(svc.isMajorityRtl('مرحبا Hello'), isFalse);
      expect(svc.isRtl('مرحبا Hello'), isTrue);
    });
  });

  group('RtlDetectionService.suggestAlignment', () {
    test('RTL → right, LTR/neutral → left', () {
      expect(svc.suggestAlignment('مرحبا'), 'right');
      expect(svc.suggestAlignment('مرحبا Hello'), 'right');
      expect(svc.suggestAlignment('Hello'), 'left');
      expect(svc.suggestAlignment('123'), 'left');
    });
  });
}
