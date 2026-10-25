import 'package:ai_pdf/features/editor/data/text_style_match.dart';

/// How an existing PDF text run can be changed with the libraries this app
/// actually ships.
enum PdfEditMode {
  /// A whiteout plus a new text box. The editor does not rewrite the source
  /// operators in place. On export, glyphs under that whiteout are removed
  /// when their widths are known; a font with no metrics still flattens the
  /// page. The new text is real PDF text when it can be, and an invisible
  /// Unicode copy when it cannot, so search still finds it.
  overlayReplacement,
}

/// Shared answer for "can this selection be edited natively?"
///
/// `pdf` 3.11 creates new PDF files. `pdfx` 2.9 renders them. Neither
/// replaces text operators inside an existing content stream, so
/// [nativeContentRewrite] stays false. Callers must not describe the overlay
/// as a native edit.
class PdfEditCapability {
  static const nativeUnavailableReason =
      'pdf 3.11 creates new PDF files and pdfx 2.9 renders them. Neither replaces text inside an existing content stream.';

  final PdfEditMode mode;
  final bool nativeContentRewrite;
  final String reason;
  final FontMatchKind fontKind;

  /// True only when [fontKind] is [FontMatchKind.exactFamily], which itself
  /// requires a bundled TrueType file that passed validation.
  final bool bundledFaceLoaded;

  const PdfEditCapability({
    this.mode = PdfEditMode.overlayReplacement,
    this.nativeContentRewrite = false,
    this.reason = nativeUnavailableReason,
    required this.fontKind,
    required this.bundledFaceLoaded,
  });
}
