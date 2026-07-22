/// Where a Bates stamp sits on the page (Phase 22).
enum BatesPosition {
  topLeft,
  topCenter,
  topRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// How to number a run of pages with Bates labels.
class BatesConfig {
  /// Text before the number, e.g. `"ABC-"`.
  final String prefix;

  /// Text after the number, e.g. `"-CONF"`.
  final String suffix;

  /// The number assigned to the first stamped page.
  final int start;

  /// Zero‑pad the numeric part to this width (e.g. 6 => `000123`). Values <= 0
  /// disable padding.
  final int padding;

  /// Increment between consecutive pages (usually 1).
  final int step;

  final BatesPosition position;

  const BatesConfig({
    this.prefix = '',
    this.suffix = '',
    this.start = 1,
    this.padding = 6,
    this.step = 1,
    this.position = BatesPosition.bottomRight,
  });
}

/// A single computed Bates stamp.
class BatesStamp {
  /// Zero‑based page index this stamp belongs to.
  final int pageIndex;

  /// The numeric value (before padding/affixes).
  final int number;

  /// The fully formatted label, e.g. `"ABC-000123-CONF"`.
  final String label;

  const BatesStamp({
    required this.pageIndex,
    required this.number,
    required this.label,
  });
}

/// Generates sequential Bates numbers for legal/enterprise page stamping
/// (Phase 22).
///
/// Bates numbering applies a unique, incrementing identifier to every page of
/// a document set — a staple of legal discovery and records management. This
/// service owns the label math (prefix/suffix, zero‑padding, start, step) and
/// hands back one [BatesStamp] per page in a chosen [pageOrder]; the caller
/// places a text annotation at [BatesConfig.position].
///
/// Pure Dart, no Flutter dependency → fully unit‑testable.
class BatesNumberingService {
  const BatesNumberingService();

  /// Stamp every page `0..pageCount-1` in natural order.
  List<BatesStamp> generate(int pageCount, BatesConfig config) {
    return generateForOrder(
      List<int>.generate(pageCount, (i) => i),
      config,
    );
  }

  /// Stamp the given [pageOrder] (already the pages to number, in the order the
  /// numbers should ascend — supports subsets and custom orderings).
  List<BatesStamp> generateForOrder(List<int> pageOrder, BatesConfig config) {
    final stamps = <BatesStamp>[];
    var number = config.start;
    for (final pageIndex in pageOrder) {
      stamps.add(BatesStamp(
        pageIndex: pageIndex,
        number: number,
        label: format(number, config),
      ));
      number += config.step;
    }
    return stamps;
  }

  /// Format a single number using [config]'s affixes and padding.
  String format(int number, BatesConfig config) {
    final digits = number.abs().toString();
    final padded = config.padding > 0
        ? digits.padLeft(config.padding, '0')
        : digits;
    final sign = number < 0 ? '-' : '';
    return '${config.prefix}$sign$padded${config.suffix}';
  }
}
