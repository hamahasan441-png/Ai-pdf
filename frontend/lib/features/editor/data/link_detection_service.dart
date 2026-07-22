import 'dart:ui' show Rect;

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// The kind of link found in the text layer (Phase 23).
enum LinkKind { url, email, phone }

/// A detected, clickable link inside the native text layer.
class DetectedLink {
  final int pageIndex;
  final int elementIndex;

  /// The raw matched text as it appears in the document.
  final String text;

  /// A ready‑to‑open href: `https://…`, `mailto:…`, or `tel:…`.
  final String href;

  final LinkKind kind;

  /// Char offsets of the match within the element's text.
  final int start;
  final int end;

  /// Normalised bounding rect of the element containing the link.
  final Rect rect;

  const DetectedLink({
    required this.pageIndex,
    required this.elementIndex,
    required this.text,
    required this.href,
    required this.kind,
    required this.start,
    required this.end,
    required this.rect,
  });

  @override
  String toString() => 'DetectedLink($kind "$text" -> $href)';
}

/// Auto‑detects URLs, emails and phone numbers in the native text layer and
/// turns them into clickable links (Phase 23).
///
/// Many PDFs contain link‑looking text with no actual link annotation. This
/// service scans each [PdfTextElement] for web addresses, email addresses and
/// phone numbers, resolves each to a normalised href (`https:` / `mailto:` /
/// `tel:`), and returns [DetectedLink]s the editor can render as tappable
/// overlays. Emails and URLs take priority over phone matches so an address
/// isn't also mis‑read as a number.
///
/// Pure Dart (regex + `dart:ui` geometry) → fully unit‑testable.
class LinkDetectionService {
  const LinkDetectionService();

  static final RegExp _emailRe = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
  );

  static final RegExp _urlRe = RegExp(
    r'(?:https?://|www\.)[^\s,;]+',
    caseSensitive: false,
  );

  // A loose phone matcher; validated afterwards by digit count.
  static final RegExp _phoneRe = RegExp(
    r'\+?\d[\d\s().\-]{5,}\d',
  );

  /// Detect links across every page of the text layer.
  List<DetectedLink> detect(Map<int, List<PdfTextElement>> pages) {
    final out = <DetectedLink>[];
    final pageIndexes = pages.keys.toList()..sort();
    for (final pageIndex in pageIndexes) {
      final elements = pages[pageIndex] ?? const [];
      for (var e = 0; e < elements.length; e++) {
        out.addAll(_detectInElement(pageIndex, e, elements[e]));
      }
    }
    return out;
  }

  /// Detect links within a single string (no positioning).
  List<DetectedLink> detectInText(String text) {
    return _detectInElement(
      0,
      0,
      PdfTextElement(text: text, rect: Rect.zero, fontSize: 0),
    );
  }

  List<DetectedLink> _detectInElement(
    int pageIndex,
    int elementIndex,
    PdfTextElement element,
  ) {
    final text = element.text;
    final taken = <List<int>>[]; // accepted [start,end) ranges

    bool overlaps(int s, int en) {
      for (final r in taken) {
        if (s < r[1] && r[0] < en) return true;
      }
      return false;
    }

    final found = <DetectedLink>[];

    void scan(RegExp re, LinkKind kind) {
      for (final m in re.allMatches(text)) {
        final s = m.start;
        final en = m.end;
        if (overlaps(s, en)) continue;
        final raw = text.substring(s, en);
        if (kind == LinkKind.phone && !_isValidPhone(raw)) continue;
        taken.add([s, en]);
        found.add(DetectedLink(
          pageIndex: pageIndex,
          elementIndex: elementIndex,
          text: raw,
          href: _href(raw, kind),
          kind: kind,
          start: s,
          end: en,
          rect: element.rect,
        ));
      }
    }

    // Priority: email, then url, then phone.
    scan(_emailRe, LinkKind.email);
    scan(_urlRe, LinkKind.url);
    scan(_phoneRe, LinkKind.phone);

    found.sort((a, b) => a.start.compareTo(b.start));
    return found;
  }

  bool _isValidPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    return digits.length >= 7 && digits.length <= 15;
  }

  String _href(String raw, LinkKind kind) {
    switch (kind) {
      case LinkKind.email:
        return 'mailto:$raw';
      case LinkKind.phone:
        final sign = raw.trimLeft().startsWith('+') ? '+' : '';
        final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
        return 'tel:$sign$digits';
      case LinkKind.url:
        final lower = raw.toLowerCase();
        if (lower.startsWith('http://') || lower.startsWith('https://')) {
          return raw;
        }
        return 'https://$raw';
    }
  }
}
