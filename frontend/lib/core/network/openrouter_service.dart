import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../config/app_settings.dart';

/// Raised when an AI request cannot be completed. [message] is user-friendly.
class OpenRouterException implements Exception {
  final String message;
  OpenRouterException(this.message);
  @override
  String toString() => message;
}

/// Direct, on-device AI client via OpenRouter (or any OpenAI-compatible API).
///
/// Features:
/// - Single API key → access GPT-4o, Claude, Gemini, Llama, DeepSeek, etc.
/// - Auto-retry: if the chosen model fails (404/400), retries once with the
///   default free fallback model so the user isn't left stuck.
/// - Multimodal: text + images (rendered PDF pages, picked photos).
/// - Works with both OpenRouter (online) and local servers (offline/LAN).
class OpenRouterService {
  OpenRouterService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 180),
        ));

  final Dio _dio;

  /// Build a data URL for an image to embed in a request.
  static String dataUrl(Uint8List bytes, {String mime = 'image/jpeg'}) =>
      'data:$mime;base64,${base64Encode(bytes)}';

  /// Ask a single question, optionally with images (as data URLs).
  Future<String> ask({
    required String prompt,
    List<String> imageUrls = const [],
    String? systemPrompt,
    String? model,
  }) {
    final userContent = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
      for (final url in imageUrls)
        {'type': 'image_url', 'image_url': {'url': url}},
    ];
    return chat([
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userContent},
    ], model: model);
  }

  /// Multi-turn chat with auto-fallback on model failure.
  ///
  /// If the chosen model returns 400/404 (model broken/gone/no vision), the
  /// service retries ONCE with the default free model so the user isn't stuck.
  Future<String> chat(
    List<Map<String, dynamic>> messages, {
    String? model,
  }) async {
    final chosenModel = model ?? AppSettings.instance.aiModel;
    try {
      return await _doChat(messages, chosenModel);
    } on OpenRouterException catch (e) {
      // Auto-fallback: if model-specific error and we haven't already tried the default
      if (e.message.contains('no longer exists') ||
          e.message.contains('not accept images') ||
          e.message.contains('not available')) {
        final fallback = AppConfig.defaultAiModel;
        if (fallback != chosenModel) {
          // Retry with default free model
          return await _doChat(messages, fallback);
        }
      }
      rethrow;
    }
  }

  Future<String> _doChat(List<Map<String, dynamic>> messages, String model) async {
    final endpoint = AppSettings.instance.aiEndpoint;
    final needsKey = AppSettings.instance.isOpenRouterEndpoint;
    final key = await AppSettings.instance.openRouterKey();

    if ((key == null || key.isEmpty) && needsKey) {
      throw OpenRouterException(
        'No API key set. Open AI Settings (key icon on home screen) and paste '
        'your OpenRouter key. Get a free one at openrouter.ai/keys.',
      );
    }

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://github.com/ai-pdf',
      'X-Title': 'AI PDF',
    };
    if (key != null && key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
    }

    try {
      final resp = await _dio.post(
        endpoint,
        options: Options(headers: headers),
        data: {
          'model': model,
          'messages': messages,
          // Allow large responses for document understanding
          'max_tokens': 4096,
        },
      );

      final data = resp.data;
      final choices = (data is Map) ? data['choices'] as List? : null;
      if (choices == null || choices.isEmpty) {
        throw OpenRouterException('The AI returned an empty response. Try again.');
      }
      final content = choices.first['message']?['content'];
      if (content is String && content.trim().isNotEmpty) return content.trim();
      if (content is List) {
        final text = content
            .whereType<Map>()
            .map((p) => p['text']?.toString() ?? '')
            .join('\n')
            .trim();
        if (text.isNotEmpty) return text;
      }
      throw OpenRouterException('The AI returned no readable text.');
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
          throw OpenRouterException(
              'Connection timed out. Check your internet and try again.');
        case DioExceptionType.receiveTimeout:
          throw OpenRouterException(
              'The AI is taking too long. This can happen with large documents. Try again or use a faster model.');
        case DioExceptionType.connectionError:
          throw OpenRouterException(
              'No internet connection. Check Wi-Fi/mobile data, or switch to an offline AI endpoint in Settings.');
        default:
          break;
      }
      final code = e.response?.statusCode;
      final errorBody = e.response?.data;
      final detail = (errorBody is Map)
          ? (errorBody['error']?['message']?.toString() ??
              errorBody['message']?.toString())
          : null;

      if (code == 401 || code == 403) {
        throw OpenRouterException(
            'API key is invalid or expired. Open AI Settings and check/replace your key.');
      }
      if (code == 402) {
        throw OpenRouterException(
            'This model ($model) requires credits. Switch to a free model in AI Settings, '
            'or top up your OpenRouter account.');
      }
      if (code == 429) {
        throw OpenRouterException(
            'Rate limit reached. Free models have a daily cap. Wait 1 minute or switch to another model.');
      }
      if (code == 400 || code == 404) {
        throw OpenRouterException(
            'Model "$model" is not available or does not accept images. '
            'Switch to another model in AI Settings.');
      }
      if (code != null && code >= 500) {
        throw OpenRouterException(
            'The AI service is down (error $code). This is temporary — try again in a minute.');
      }
      throw OpenRouterException(detail ?? 'Network error. Check your connection and try again.');
    } catch (e) {
      if (e is OpenRouterException) rethrow;
      throw OpenRouterException('AI request failed: $e');
    }
  }
}
