import 'package:pdf/widgets.dart' as pw;

/// The 14 built-in PDF standard fonts, created once and reused across pages
/// during export. Standard fonts keep the exported text selectable/searchable
/// without bundling any TTF assets (Latin-1 coverage only — non-Latin text is
/// rasterized into the page image instead).
class EditorPdfFonts {
  final pw.Font helv = pw.Font.helvetica();
  final pw.Font helvB = pw.Font.helveticaBold();
  final pw.Font helvO = pw.Font.helveticaOblique();
  final pw.Font helvBO = pw.Font.helveticaBoldOblique();
  final pw.Font times = pw.Font.times();
  final pw.Font timesB = pw.Font.timesBold();
  final pw.Font timesI = pw.Font.timesItalic();
  final pw.Font timesBI = pw.Font.timesBoldItalic();
  final pw.Font cour = pw.Font.courier();
  final pw.Font courB = pw.Font.courierBold();
  final pw.Font courO = pw.Font.courierOblique();
  final pw.Font courBO = pw.Font.courierBoldOblique();

  /// Pick the standard font matching the editor's [family] ('serif' -> Times,
  /// 'monospace' -> Courier, else Helvetica) and bold/italic style.
  pw.Font pick(String? family, bool bold, bool italic) {
    switch (family) {
      case 'serif':
        return bold ? (italic ? timesBI : timesB) : (italic ? timesI : times);
      case 'monospace':
        return bold ? (italic ? courBO : courB) : (italic ? courO : cour);
      default:
        return bold ? (italic ? helvBO : helvB) : (italic ? helvO : helv);
    }
  }
}
