/// The post-capture enhancement applied to a scanned page (Phase 51).
enum ScanFilter {
  /// No enhancement — the dewarped colour photo as-is.
  original,

  /// "Magic colour" — white balance + contrast stretch for a clean, bright
  /// document look while keeping colour (the default for most scanners).
  auto,

  /// Grayscale (colour removed, tones preserved).
  grayscale,

  /// High-contrast black & white via Sauvola adaptive thresholding — best for
  /// text documents and smallest file size.
  blackWhite,

  /// Photo mode — gentle contrast/saturation boost, preserves gradients.
  photo,
}
