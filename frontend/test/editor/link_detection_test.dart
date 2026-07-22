import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/link_detection_service.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

PdfTextElement _el(String text) =>
    PdfTextElement(text: text, rect: const Rect.fromLTWH(0.1, 0.2, 0.5, 0.05), fontSize: 12);

void main() {
  const svc = LinkDetectionService();

  group('LinkDetectionService (Phase 23)', () {
    test('detects https url and preserves the scheme', () {
      final links = svc.detectInText('see https://example.com/docs for more');
      expect(links.length, 1);
      expect(links.single.kind, LinkKind.url);
      expect(links.single.href, 'https://example.com/docs');
    });

    test('bare www url gets an https scheme', () {
      final links = svc.detectInText('visit www.example.org today');
      expect(links.single.kind, LinkKind.url);
      expect(links.single.href, 'https://www.example.org');
    });

    test('email becomes a mailto href', () {
      final links = svc.detectInText('write to jane.doe@example.co.uk please');
      expect(links.single.kind, LinkKind.email);
      expect(links.single.href, 'mailto:jane.doe@example.co.uk');
    });

    test('phone becomes a tel href with digits only (keeps +)', () {
      final links = svc.detectInText('call +49 (170) 123-4567 now');
      final phone = links.firstWhere((l) => l.kind == LinkKind.phone);
      expect(phone.href, 'tel:+491701234567');
    });

    test('an email is not also mis-detected as a phone number', () {
      final links = svc.detectInText('contact 12345@678901.com');
      expect(links.where((l) => l.kind == LinkKind.email).length, 1);
      expect(links.where((l) => l.kind == LinkKind.phone), isEmpty);
    });

    test('too-short digit runs are not phones', () {
      final links = svc.detectInText('room 12 34');
      expect(links, isEmpty);
    });

    test('detect across pages carries page/element indices and rect', () {
      final pages = <int, List<PdfTextElement>>{
        0: [_el('plain'), _el('mail me at a@b.com')],
        1: [_el('http://x.io')],
      };
      final links = svc.detect(pages);
      expect(links.length, 2);
      expect(links[0].pageIndex, 0);
      expect(links[0].elementIndex, 1);
      expect(links[0].kind, LinkKind.email);
      expect(links[0].rect, const Rect.fromLTWH(0.1, 0.2, 0.5, 0.05));
      expect(links[1].pageIndex, 1);
      expect(links[1].kind, LinkKind.url);
    });

    test('multiple links in one element are ordered by position', () {
      final links = svc.detectInText('a@b.com then https://c.dev');
      expect(links.map((l) => l.kind), [LinkKind.email, LinkKind.url]);
      expect(links.first.start, lessThan(links.last.start));
    });
  });
}
