/// Application configuration constants.
class AppConfig {
  AppConfig._();

  static const String appName = 'AI Document Assistant';
  static const String apiBaseUrl = 'http://localhost:8000/api/v1';
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxUploadSizeMB = 50;

  // Supported file types
  static const List<String> supportedFileExtensions = [
    'pdf',
    'docx',
    'png',
    'jpg',
    'jpeg',
  ];

  // Pagination
  static const int defaultPageSize = 20;
}
