import 'package:shared_preferences/shared_preferences.dart';

/// Export quality settings — user chooses resolution and format.
///
/// Gives users control over the trade-off between file size and quality:
/// - High quality (2400px) — default, best for printing
/// - Medium quality (1600px) — smaller files, good for sharing
/// - Low quality (1000px) — smallest files, for email/messaging
///
/// Also controls whether Latin text is exported as vector (searchable) or
/// rasterized (smaller, simpler).
class ExportSettingsService {
  static const String _qualityKey = 'export_quality';
  static const String _vectorTextKey = 'export_vector_text';
  static const String _flattenKey = 'export_flatten';

  const ExportSettingsService();

  /// Get the current export quality setting.
  Future<ExportQuality> getQuality() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_qualityKey) ?? 'high';
    return ExportQuality.values.firstWhere(
      (q) => q.name == value,
      orElse: () => ExportQuality.high,
    );
  }

  /// Set the export quality.
  Future<void> setQuality(ExportQuality quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qualityKey, quality.name);
  }

  /// Whether to export Latin text as vector (searchable).
  Future<bool> useVectorText() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vectorTextKey) ?? true; // default: yes
  }

  /// Set vector text preference.
  Future<void> setVectorText(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vectorTextKey, enabled);
  }

  /// Whether to flatten all annotations into the page (non-editable output).
  Future<bool> shouldFlatten() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_flattenKey) ?? true; // default: yes (standard)
  }

  /// Set flatten preference.
  Future<void> setFlatten(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flattenKey, enabled);
  }

  /// Get the max edge pixels for the current quality setting.
  Future<int> maxEdgePixels() async {
    final quality = await getQuality();
    return quality.maxEdge;
  }
}

/// Export quality levels.
enum ExportQuality {
  high(maxEdge: 2400, label: 'High (print quality)'),
  medium(maxEdge: 1600, label: 'Medium (sharing)'),
  low(maxEdge: 1000, label: 'Low (email/messaging)');

  final int maxEdge;
  final String label;
  const ExportQuality({required this.maxEdge, required this.label});
}
