import 'dart:ui' show Offset;

/// A computed watermark layout: where to stamp the mark, and how (Phase 19).
class WatermarkPlan {
  /// Normalised 0..1 centre points where the watermark should be drawn.
  final List<Offset> positions;

  /// Rotation applied to each stamp, in degrees (negative = counter‑clockwise).
  final double angleDegrees;

  /// Stamp opacity, 0..1.
  final double opacity;

  const WatermarkPlan({
    required this.positions,
    required this.angleDegrees,
    required this.opacity,
  });

  int get count => positions.length;
}

/// Computes watermark placement over a page (Phase 19).
///
/// Produces the centre points (in the editor's normalised 0..1 page space) for
/// either a single centred watermark or a repeated, diagonally‑rotated tiled
/// pattern — the classic "CONFIDENTIAL / DRAFT" wash. The caller renders the
/// actual text or image at each point using [WatermarkPlan.angleDegrees] and
/// [WatermarkPlan.opacity]; this service owns only the geometry, so it is pure
/// Dart and fully unit‑testable.
class WatermarkService {
  const WatermarkService();

  static const double defaultAngleDegrees = -45.0;
  static const double defaultOpacity = 0.15;

  /// A single watermark centred on the page.
  WatermarkPlan single({
    double angleDegrees = defaultAngleDegrees,
    double opacity = defaultOpacity,
  }) {
    return WatermarkPlan(
      positions: const [Offset(0.5, 0.5)],
      angleDegrees: angleDegrees,
      opacity: opacity,
    );
  }

  /// A repeated tiled watermark.
  ///
  /// Centres are laid out on a grid with the given normalised [spacingX] /
  /// [spacingY], inset by half a step from the edges so marks aren't clipped.
  /// When [stagger] is true, alternate rows are shifted right by half a step
  /// for a brick‑like, harder‑to‑remove pattern.
  WatermarkPlan tiled({
    double spacingX = 0.34,
    double spacingY = 0.25,
    bool stagger = true,
    double angleDegrees = defaultAngleDegrees,
    double opacity = defaultOpacity,
  }) {
    assert(spacingX > 0 && spacingY > 0, 'spacing must be positive');
    final positions = <Offset>[];
    const eps = 1e-9;

    var row = 0;
    for (var y = spacingY / 2; y < 1 - eps; y += spacingY) {
      final startX =
          stagger && row.isOdd ? spacingX / 2 + spacingX / 2 : spacingX / 2;
      for (var x = startX; x < 1 - eps; x += spacingX) {
        positions.add(Offset(x, y));
      }
      row++;
    }

    return WatermarkPlan(
      positions: positions,
      angleDegrees: angleDegrees,
      opacity: opacity,
    );
  }
}
