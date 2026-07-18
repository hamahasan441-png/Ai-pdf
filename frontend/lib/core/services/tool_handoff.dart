/// A tiny, one-shot hand-off used to pass a freshly produced file from one tool
/// to another (e.g. the PDF editor exporting a file and continuing straight into
/// Compress / Convert / PDF→Images / Extract Text) without making the user
/// pick the file again.
///
/// The value is consumed exactly once via [take]; a screen reads it in initState
/// and it is cleared immediately so it never leaks into a later, unrelated open.
class ToolHandoff {
  ToolHandoff._();
  static final ToolHandoff instance = ToolHandoff._();

  String? _path;

  /// Queue a file to be picked up by the next tool screen that opens.
  void set(String path) => _path = path;

  /// Retrieve and clear the pending file path (null if none).
  String? take() {
    final p = _path;
    _path = null;
    return p;
  }
}
