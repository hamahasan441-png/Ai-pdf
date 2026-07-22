import 'dart:math' as math;
import 'dart:ui' show Offset;

/// A calibration mapping on‑page distance to a real‑world unit (Phase 21).
///
/// [unitsPerLength] is how many real‑world [unit]s one unit of document
/// distance represents (derived by measuring a segment of known length).
class MeasurementCalibration {
  final double unitsPerLength;
  final String unit;

  const MeasurementCalibration({
    required this.unitsPerLength,
    required this.unit,
  });

  /// The identity calibration (document units == real units).
  static const identity =
      MeasurementCalibration(unitsPerLength: 1.0, unit: 'u');
}

/// Ruler / area measurement with real‑world calibration (Phase 21).
///
/// A professional PDF feature: the user draws a segment over something of known
/// size (e.g. a scale bar or a dimension line) to [calibrate], then every
/// subsequent distance, perimeter, or area readout is reported in real units
/// (m, cm, ft…). All geometry is done in a single consistent "document unit"
/// space supplied by the caller (e.g. points or pixels), so Euclidean distance
/// is well defined.
///
/// Pure Dart (`dart:math` + `dart:ui` geometry) → fully unit‑testable.
class MeasurementService {
  const MeasurementService();

  /// Build a calibration: a segment measured as [measuredLength] document units
  /// is declared to be [realLength] [unit]s long.
  ///
  /// Throws [ArgumentError] if [measuredLength] is not positive.
  MeasurementCalibration calibrate(
    double measuredLength,
    double realLength,
    String unit,
  ) {
    if (measuredLength <= 0) {
      throw ArgumentError.value(
          measuredLength, 'measuredLength', 'must be > 0');
    }
    return MeasurementCalibration(
      unitsPerLength: realLength / measuredLength,
      unit: unit,
    );
  }

  /// Straight‑line distance between two points, in document units.
  double distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Total length of a polyline (sum of segment lengths), in document units.
  double pathLength(List<Offset> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distance(points[i - 1], points[i]);
    }
    return total;
  }

  /// Area of a (implicitly closed) polygon via the shoelace formula, in
  /// document units². Fewer than 3 points => 0.
  double polygonArea(List<Offset> points) {
    if (points.length < 3) return 0.0;
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2.0;
  }

  /// Real‑world distance between two points under [cal].
  double realDistance(Offset a, Offset b, MeasurementCalibration cal) =>
      distance(a, b) * cal.unitsPerLength;

  /// Real‑world polyline length under [cal].
  double realPathLength(List<Offset> points, MeasurementCalibration cal) =>
      pathLength(points) * cal.unitsPerLength;

  /// Real‑world polygon area under [cal] (scales by the factor squared).
  double realArea(List<Offset> points, MeasurementCalibration cal) =>
      polygonArea(points) * cal.unitsPerLength * cal.unitsPerLength;

  /// Format a measurement value with its unit, e.g. `"10.50 cm"`.
  String format(double value, String unit, {int decimals = 2}) =>
      '${value.toStringAsFixed(decimals)} $unit';
}
