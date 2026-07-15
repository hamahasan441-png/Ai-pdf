import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import '../config/app_settings.dart';
import '../constants/app_constants.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio dio;
  final _storage = const FlutterSecureStorage();

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: AppSettings.instance.apiBaseUrl,
      connectTimeout: AppConfig.requestTimeout,
      receiveTimeout: AppConfig.requestTimeout,
      headers: {'Content-Type': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: AppConstants.accessTokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final ok = await _refresh();
          if (ok) {
            final opts = error.requestOptions;
            final token = await _storage.read(key: AppConstants.accessTokenKey);
            opts.headers['Authorization'] = 'Bearer $token';
            final r = await dio.fetch(opts);
            return handler.resolve(r);
          }
        }
        handler.next(error);
      },
    ));
  }

  /// Point the client at a new server at runtime (used by Settings).
  void updateBaseUrl(String url) {
    dio.options.baseUrl = url;
  }

  Future<bool> _refresh() async {
    try {
      final rt = await _storage.read(key: AppConstants.refreshTokenKey);
      if (rt == null) return false;
      final r = await Dio(BaseOptions(baseUrl: AppSettings.instance.apiBaseUrl))
          .post(AppConstants.refreshEndpoint, data: {'refresh_token': rt});
      if (r.statusCode == 200) {
        await _storage.write(key: AppConstants.accessTokenKey, value: r.data['access_token']);
        await _storage.write(key: AppConstants.refreshTokenKey, value: r.data['refresh_token']);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> saveTokens(String access, String refresh) async {
    await _storage.write(key: AppConstants.accessTokenKey, value: access);
    await _storage.write(key: AppConstants.refreshTokenKey, value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: AppConstants.accessTokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
  }

  Future<bool> hasToken() async {
    final t = await _storage.read(key: AppConstants.accessTokenKey);
    return t != null;
  }
}
