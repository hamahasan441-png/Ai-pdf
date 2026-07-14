import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import 'api_client.dart';

enum AuthStatus { initial, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? userId;
  final String? email;
  final String? error;

  const AuthState({
    this.status = AuthStatus.initial,
    this.userId,
    this.email,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? email,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _apiClient;

  AuthNotifier(this._apiClient) : super(const AuthState());

  Future<bool> login(String email, String password) async {
    try {
      final response = await _apiClient.dio.post(
        AppConstants.loginEndpoint,
        data: {'email': email, 'password': password},
      );

      if (response.statusCode == 200) {
        await _apiClient.setTokens(
          response.data['access_token'],
          response.data['refresh_token'],
        );
        state = state.copyWith(
          status: AuthStatus.authenticated,
          email: email,
        );
        return true;
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Login failed. Please check your credentials.',
      );
    }
    return false;
  }

  Future<bool> register(String email, String password, String fullName) async {
    try {
      final response = await _apiClient.dio.post(
        AppConstants.registerEndpoint,
        data: {
          'email': email,
          'password': password,
          'full_name': fullName,
        },
      );

      if (response.statusCode == 201) {
        await _apiClient.setTokens(
          response.data['access_token'],
          response.data['refresh_token'],
        );
        state = state.copyWith(
          status: AuthStatus.authenticated,
          email: email,
        );
        return true;
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Registration failed. Please try again.',
      );
    }
    return false;
  }

  Future<void> logout() async {
    await _apiClient.clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthNotifier(apiClient);
});
