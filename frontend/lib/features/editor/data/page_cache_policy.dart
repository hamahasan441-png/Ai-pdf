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
