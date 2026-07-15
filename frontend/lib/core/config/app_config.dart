class AppConfig {
  AppConfig._();
  static const String appName = 'AI PDF';
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
  static const int maxFileSizeMB = 50;
  static const List<String> supportedExtensions = [
    'pdf', 'docx', 'doc', 'png', 'jpg', 'jpeg', 'tiff',
  ];
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);
}
