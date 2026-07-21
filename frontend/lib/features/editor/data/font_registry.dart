/// Font registry for the editor — maps font family names to asset paths.
///
/// This is the preparation for P1 font embedding (RTL export). When Noto/
/// Vazirmatn font assets are added to pubspec.yaml, the export service will
/// use this registry to look up the TTF file for embedding into the PDF.
///
/// ### Current supported families
/// The list below declares the font families the editor recognizes. Assets
/// are loaded lazily by the export service when needed.
class FontRegistry {
  const FontRegistry();

  /// All known font families with their asset paths.
  /// When fonts are added to pubspec.yaml assets, update paths here.
  static const Map<String, FontAsset> families = {
    'sans-serif': FontAsset(
      displayName: 'Sans Serif',
      regular: 'assets/fonts/NotoSans-Regular.ttf',
      bold: 'assets/fonts/NotoSans-Bold.ttf',
      italic: 'assets/fonts/NotoSans-Italic.ttf',
      boldItalic: 'assets/fonts/NotoSans-BoldItalic.ttf',
    ),
    'serif': FontAsset(
      displayName: 'Serif',
      regular: 'assets/fonts/NotoSerif-Regular.ttf',
      bold: 'assets/fonts/NotoSerif-Bold.ttf',
      italic: 'assets/fonts/NotoSerif-Italic.ttf',
      boldItalic: 'assets/fonts/NotoSerif-BoldItalic.ttf',
    ),
    'monospace': FontAsset(
      displayName: 'Monospace',
      regular: 'assets/fonts/NotoSansMono-Regular.ttf',
      bold: 'assets/fonts/NotoSansMono-Bold.ttf',
    ),
    'NotoSansArabic': FontAsset(
      displayName: 'Arabic (Noto)',
      regular: 'assets/fonts/NotoSansArabic-Regular.ttf',
      bold: 'assets/fonts/NotoSansArabic-Bold.ttf',
    ),
    'Vazirmatn': FontAsset(
      displayName: 'Kurdish/Persian (Vazirmatn)',
      regular: 'assets/fonts/Vazirmatn-Regular.ttf',
      bold: 'assets/fonts/Vazirmatn-Bold.ttf',
    ),
    'NotoSansHebrew': FontAsset(
      displayName: 'Hebrew (Noto)',
      regular: 'assets/fonts/NotoSansHebrew-Regular.ttf',
      bold: 'assets/fonts/NotoSansHebrew-Bold.ttf',
    ),
  };

  /// Resolve the asset path for a given family + style combination.
  /// Returns the regular variant if the specific style isn't available.
  String? resolve(String? family, {bool bold = false, bool italic = false}) {
    final key = family ?? 'sans-serif';
    final asset = families[key];
    if (asset == null) return null;
    if (bold && italic && asset.boldItalic != null) return asset.boldItalic;
    if (bold) return asset.bold ?? asset.regular;
    if (italic) return asset.italic ?? asset.regular;
    return asset.regular;
  }

  /// Get all available font family names for the font picker UI.
  List<String> get availableFamilies => families.keys.toList();

  /// Get display name for a family.
  String displayName(String family) =>
      families[family]?.displayName ?? family;
}

/// A font asset with paths to each style variant.
class FontAsset {
  final String displayName;
  final String regular;
  final String? bold;
  final String? italic;
  final String? boldItalic;

  const FontAsset({
    required this.displayName,
    required this.regular,
    this.bold,
    this.italic,
    this.boldItalic,
  });
}
