/// Application-wide constants.
class AppConstants {
  AppConstants._();

  // Storage keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userDataKey = 'user_data';

  // API endpoints
  static const String loginEndpoint = '/auth/login';
  static const String registerEndpoint = '/auth/register';
  static const String refreshEndpoint = '/auth/refresh';
  static const String profileEndpoint = '/profile';
  static const String documentsEndpoint = '/documents';
  static const String uploadEndpoint = '/documents/upload';

  // Document statuses
  static const String statusUploaded = 'uploaded';
  static const String statusProcessing = 'processing';
  static const String statusAnalyzed = 'analyzed';
  static const String statusFormDetected = 'form_detected';
  static const String statusFilled = 'filled';
  static const String statusExported = 'exported';
  static const String statusError = 'error';

  // UI
  static const double maxContentWidth = 1200.0;
  static const double cardElevation = 2.0;
  static const double borderRadius = 12.0;
}
