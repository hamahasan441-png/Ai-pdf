import 'dart:math' as math;

/// Decides when a cached page bitmap is sharp enough, and when a finished
/// render is allowed to replace what is already on screen.
///
/// Kept free of pdfx so the editor can unit-test the policy without rendering.
class PageCachePolicy {
  const PageCachePolicy._();

  /// True when [pageCache] already holds a bitmap at least as sharp as
  /// [requestedEdge]. When [tracksResolution] is false, any cached bytes count
  /// (legacy callers that only ever render one size).
  static bool shouldSkip({
    required bool hasBytes,
    required int? cachedEdge,
    required int requestedEdge,
    required bool tracksResolution,
  }) {
    if (!hasBytes) return false;
    if (!tracksResolution) return true;
    if (cachedEdge == null) return false;
    return cachedEdge >= requestedEdge;
  }

  /// A slower low-resolution render must not overwrite a sharper bitmap that
  /// finished first.
  static bool shouldStore({
    required int? cachedEdge,
    required int renderedEdge,
  }) {
    if (cachedEdge == null) return true;
    return renderedEdge >= cachedEdge;
  }
}

/// Pixel size for a PDF page whose [pageWidth]/[pageHeight] are in PDF points.
///
/// pdfx reports the media box in points (1/72"). Treating that number as
/// pixels leaves an A4 page around 800px and then records the requested cap
/// (2400) as if the JPEG were that sharp. This always targets [renderMaxEdge]
/// on the long side, and still caps oversized pages.
({double width, double height, int edge}) planPageRenderSize({
  required double pageWidth,
  required double pageHeight,
  required num renderMaxEdge,
}) {
  final longEdge = math.max(pageWidth, pageHeight);
  final cap = renderMaxEdge.round();
  if (longEdge <= 0 || !longEdge.isFinite || cap <= 0) {
    return (width: 1, height: 1, edge: 1);
  }
  final scale = cap / longEdge;
  final width = math.max(1.0, pageWidth * scale);
  final height = math.max(1.0, pageHeight * scale);
  final edge = math.max(width, height).round().clamp(1, cap);
  return (width: width, height: height, edge: edge);
}
