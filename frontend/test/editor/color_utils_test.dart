import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/color_utils_service.dart';

void main() {
  const svc = ColorUtilsService();
  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);
  const red = Color(0xFFFF0000);

  group('ColorUtilsService (Phase 24)', () {
    test('parseHex handles #RGB, #RRGGBB, #AARRGGBB and bare forms', () {
      expect(svc.parseHex('#FF0000'), red);
      expect(svc.parseHex('FF0000'), red);
      expect(svc.parseHex('#F00'), red); // shorthand expands
      expect(svc.parseHex('#80FF0000'), const Color(0x80FF0000));
    });

    test('parseHex rejects malformed input', () {
      expect(svc.parseHex('#12'), isNull);
      expect(svc.parseHex('#GGGGGG'), isNull);
      expect(svc.parseHex('nope'), isNull);
    });

    test('toHex round-trips', () {
      expect(svc.toHex(red), '#FF0000');
      expect(svc.toHex(const Color(0x80FF0000), includeAlpha: true), '#80FF0000');
      expect(svc.parseHex(svc.toHex(const Color(0xFF123456))),
          const Color(0xFF123456));
    });

    test('contrast ratio of black on white is 21:1', () {
      expect(svc.contrastRatio(black, white), closeTo(21.0, 1e-6));
      // order-independent
      expect(svc.contrastRatio(white, black), closeTo(21.0, 1e-6));
    });

    test('relative luminance extremes', () {
      expect(svc.relativeLuminance(black), closeTo(0.0, 1e-9));
      expect(svc.relativeLuminance(white), closeTo(1.0, 1e-9));
    });

    test('isReadable applies the WCAG AA threshold', () {
      expect(svc.isReadable(black, white), isTrue);
      expect(svc.isReadable(const Color(0xFFCCCCCC), white), isFalse);
    });

    test('bestTextColor picks the higher-contrast option', () {
      expect(svc.bestTextColor(white), black);
      expect(svc.bestTextColor(black), white);
      expect(svc.bestTextColor(const Color(0xFF222222)), white);
    });

    test('lighten toward white, darken toward black; alpha preserved', () {
      expect(svc.lighten(black, 1.0), const Color(0xFFFFFFFF));
      expect(svc.darken(white, 1.0), const Color(0xFF000000));
      // half-lighten black -> mid gray (128)
      final g = svc.lighten(black, 0.5);
      expect(g.red, 128);
      expect(g.green, 128);
      expect(g.blue, 128);
      // alpha preserved
      expect(svc.lighten(const Color(0x80FF0000), 0.5).alpha, 0x80);
    });

    test('lighten/darken clamp the amount', () {
      expect(svc.lighten(red, 2.0), const Color(0xFFFFFFFF));
      expect(svc.darken(red, -1.0), red); // no change
    });
  });
}
