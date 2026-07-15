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

/// Direct, on-device OpenRouter client.
///
/// Calls OpenRouter's OpenAI-compatible chat/completions endpoint straight
/// from the phone using the user's own key (from encrypted device storage or
/// an optional build-time value). No backend server is required.
///
/// Supports multimodal input: text plus one or more images (e.g. rendered PDF
/// pages or a picked photo) so the app can "understand" any document.
class OpenRouterService {
  OpenRouterService() : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ));

  final Dio _dio;

  /// Build a data URL for an image to embed in a request.
  static String dataUrl(Uint8List bytes, {String mime = 'image/jpeg'}) =>
      'data:$mime;base64,${base64Encode(bytes)}';

  /// Ask a single question, optionally with images (as data URLs).
  /// Convenience wrapper around [chat].
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

  /// Multi-turn chat. [messages] is the full OpenAI-style message list
  /// (system/user/assistant). Content may be a String or a list of parts
  /// (for images). Returns the assistant's reply text.
  Future<String> chat(
    List<Map<String, dynamic>> messages, {
    String? model,
  }) async {
    final key = await AppSettings.instance.openRouterKey();
    if (key == null || key.isEmpty) {
      throw OpenRouterException(
        'No AI key yet. Go to Profile and paste your OpenRouter API key to enable AI.',
      );
    }

    try {
      final resp = await _dio.post(
        AppConfig.openRouterUrl,
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://github.com/ai-pdf',
          'X-Title': 'AI PDF',
        }),
        data: {
          'model': model ?? AppSettings.instance.aiModel,
          'messages': messages,
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
      final code = e.response?.statusCode;
      if (code == 401) {
        throw OpenRouterException('Invalid API key. Check your OpenRouter key in Profile.');
      }
      if (code == 402) {
        throw OpenRouterException('This model needs credits. Pick a free model in Profile.');
      }
      if (code == 429) {
        throw OpenRouterException('Rate limit hit. Wait a moment or pick another free model.');
      }
      if (code == 400 || code == 404) {
        throw OpenRouterException(
            'This model may not accept images or no longer exists. Try another model in Profile.');
      }
      final detail = e.response?.data is Map
          ? (e.response?.data['error']?['message']?.toString())
          : null;
      throw OpenRouterException(detail ?? 'Network error contacting AI. Check your connection.');
    } catch (e) {
      if (e is OpenRouterException) rethrow;
      throw OpenRouterException('AI request failed: $e');
    }
  }
}
