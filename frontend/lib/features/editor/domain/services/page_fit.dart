/// Fits one PDF page inside a viewport without assuming A4.
///
/// [aspect] is width / height of the real page (MediaBox, or the rotated
/// bitmap the user is looking at). Coordinates elsewhere stay normalised
/// 0..1 inside this box, so preview, hit testing, and export share one frame.
class PageFit {
  static const double a4PortraitAspect = 1 / 1.41421356237;

  const PageFit._();

  static ({double width, double height, double left, double top}) box({
    required double maxWidth,
    required double maxHeight,
    double aspect = a4PortraitAspect,
  }) {
    if (maxWidth <= 0 || maxHeight <= 0) {
      return (width: 0, height: 0, left: 0, top: 0);
    }
    var a = aspect;
    if (a <= 0 || a.isNaN || a.isInfinite) a = a4PortraitAspect;
    final double width;
    final double height;
    if (maxWidth / maxHeight > a) {
      height = maxHeight;
      width = maxHeight * a;
    } else {
      width = maxWidth;
      height = maxWidth / a;
    }
    return (
      width: width,
      height: height,
      left: (maxWidth - width) / 2,
      top: (maxHeight - height) / 2,
    );
  }
}
