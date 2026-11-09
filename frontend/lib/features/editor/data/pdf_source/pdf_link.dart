import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';

/// A link the editor adds. [rect] is 0..1 from the displayed top left
/// (left, top, right, bottom). Either a web address or a page of this file.
class PdfLinkSpec {
  final List<double> rect;
  final String? uri;
  final int? page;

  const PdfLinkSpec({required this.rect, this.uri, this.page});
}

/// A web address or a mailto link. A bare host gets https. Anything else
/// is refused so a mistyped box does not become a broken link.
String? normalizeLinkUri(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text.contains(' ') || text.contains('\n')) return null;
  final withScheme = text.contains('://') || text.startsWith('mailto:') ? text : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme == 'mailto') return uri.path.isEmpty ? null : uri.toString();
  if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
  return uri.toString();
}

/// The PDF action for [link], or null when it points nowhere.
/// [pages] is the output page list, in order.
PdfDict? linkAction(PdfLinkSpec link, List<PdfValue> pages) {
  final uri = link.uri == null ? null : normalizeLinkUri(link.uri!);
  if (uri != null) {
    return PdfDict({
      '/S': const PdfName('/URI'),
      '/URI': PdfString.ofText(uri),
    });
  }
  final page = link.page;
  if (page == null || page < 0 || page >= pages.length) return null;
  final dest = pages[page];
  if (dest is! PdfRef) return null;
  return PdfDict({
    '/S': const PdfName('/GoTo'),
    '/D': PdfArray([dest, const PdfName('/Fit')]),
  });
}
