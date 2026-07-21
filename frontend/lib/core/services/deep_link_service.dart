/// Deep link handler — opens PDFs/images from other apps.
///
/// When another app shares a file with AI-PDF (via Android's intent system),
/// this service receives the file path and routes it to the appropriate screen
/// (editor for PDFs/images, AI chat for text documents).
///
/// ### Supported intents
/// - ACTION_VIEW with a file:// or content:// URI
/// - ACTION_SEND with a single file attachment
/// - ACTION_SEND_MULTIPLE with multiple files
///
/// ### Architecture
/// The native Android side (MainActivity/IntentFilter) passes the URI(s) to
/// Flutter via a MethodChannel. This service processes them and navigates.
class DeepLinkService {
  static const String channelName = 'com.aidocassistant.app/deeplink';

  const DeepLinkService();

  /// Determine the target route for a received file.
  String routeForFile(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.pdf')) return '/tools/pick-edit';
    if (_isImage(lower)) return '/tools/pick-edit';
    if (_isDocument(lower)) return '/ai'; // AI chat for text docs
    return '/tools/pick-edit'; // default: editor
  }

  /// Check if a file is a supported type.
  bool isSupported(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.endsWith('.pdf') || _isImage(lower) || _isDocument(lower);
  }

  /// Get a user-friendly label for the file type.
  String fileTypeLabel(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.pdf')) return 'PDF';
    if (_isImage(lower)) return 'Image';
    if (lower.endsWith('.docx') || lower.endsWith('.doc')) return 'Word';
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) return 'Excel';
    return 'File';
  }

  bool _isImage(String lower) =>
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.bmp');

  bool _isDocument(String lower) =>
      lower.endsWith('.docx') ||
      lower.endsWith('.doc') ||
      lower.endsWith('.txt') ||
      lower.endsWith('.rtf');
}
