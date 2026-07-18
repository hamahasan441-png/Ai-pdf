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

/// Direct, on-device multi-provider AI client.
///
/// Supports several providers with the user's own key:
/// - OpenRouter, OpenAI, Perplexity, custom/local → OpenAI "chat/completions".
/// - Anthropic (Claude) → the Anthropic "messages" API (different headers and
///   request/response shape), handled separately.
///
/// (Class name kept as OpenRouterService for compatibility with existing call
/// sites; it is now provider-agnostic.)
class OpenRouterService {
  OpenRouterService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 180),
        ));

  final Dio _dio;

  /// The model slug actually used by the last successful call.
  String? lastModelUsed;

  /// Build a data URL for an image to embed in a request.
  static String dataUrl(Uint8List bytes, {String mime = 'image/jpeg'}) =>
      'data:$mime;base64,${base64Encode(bytes)}';

  static bool _hasImages(List<Map<String, dynamic>> messages) {
    for (final m in messages) {
      final c = m['content'];
      if (c is List && c.any((p) => p is Map && p['type'] == 'image_url')) {
        return true;
      }
    }
    return false;
  }

  /// Resolve 'auto' (OpenRouter only) to a concrete free model based on whether
  /// the request has images. Real slugs pass through unchanged.
  static String _resolveModel(String model, List<Map<String, dynamic>> messages) {
    if (model != AppConfig.autoModel) return model;
    return _hasImages(messages) ? AppConfig.autoVisionModel : AppConfig.autoTextModel;
  }

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

  /// Multi-turn chat. [messages] is the OpenAI-style message list; images are
  /// image_url parts with data URLs. Dispatches to the right provider API.
  Future<String> chat(
    List<Map<String, dynamic>> messages, {
    String? model,
  }) async {
    final settings = AppSettings.instance;
    if (settings.isManaged) {
      final reply = await _doManagedChat(messages);
      lastModelUsed = 'managed';
      return reply;
    }
    final chosen = model ?? settings.aiModel;
    final resolved = _resolveModel(chosen, messages);
    final isOpenRouter = settings.providerId == AppConfig.providerOpenRouter;

    try {
      final reply = await _doChat(messages, resolved);
      lastModelUsed = resolved;
      return reply;
    } on OpenRouterException catch (e) {
      // Auto-fallback only makes sense on OpenRouter (its free slugs).
      final modelIssue = e.message.contains('no longer exists') ||
          e.message.contains('not accept images') ||
          e.message.contains('not available') ||
          e.message.contains('is not available');
      if (isOpenRouter && modelIssue) {
        final fallback = _hasImages(messages)
            ? AppConfig.autoVisionModel
            : AppConfig.autoTextModel;
        if (fallback != resolved) {
          final reply = await _doChat(messages, fallback);
          lastModelUsed = fallback;
          return reply;
        }
      }
      rethrow;
    }
  }

  /// Streaming chat for OpenAI-compatible providers. Calls [onDelta] with each
  /// text chunk as it arrives and returns the full text. Anthropic (different
  /// SSE format) transparently falls back to a single non-streamed response.
  Future<String> chatStream(
    List<Map<String, dynamic>> messages, {
    String? model,
    required void Function(String delta) onDelta,
  }) async {
    final settings = AppSettings.instance;
    // Managed proxy: no streaming protocol — do a single call and emit it whole.
    if (settings.isManaged) {
      final full = await _doManagedChat(messages);
      lastModelUsed = 'managed';
      if (full.isNotEmpty) onDelta(full);
      return full;
    }
    final chosen = model ?? settings.aiModel;
    final resolved = _resolveModel(chosen, messages);

    // Anthropic uses a different streaming protocol — just do a normal call.
    if (settings.isAnthropic) {
      final full = await _doChat(messages, resolved);
      lastModelUsed = resolved;
      if (full.isNotEmpty) onDelta(full);
      return full;
    }

    final endpoint = settings.aiEndpoint;
    final key = await settings.apiKey();
    if (settings.needsKey && (key == null || key.isEmpty)) {
      throw OpenRouterException(
        'No API key set for ${settings.provider.label}. Open AI Settings and paste your key.',
      );
    }
    if (endpoint.isEmpty) {
      throw OpenRouterException('No AI endpoint set. Choose a provider in AI Settings.');
    }

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://github.com/ai-pdf',
      'X-Title': 'Pdoczy',
    };
    if (key != null && key.isNotEmpty) headers['Authorization'] = 'Bearer $key';

    try {
      final resp = await _dio.post(
        endpoint,
        options: Options(headers: headers, responseType: ResponseType.stream),
        data: {'model': resolved, 'messages': messages, 'max_tokens': 4096, 'stream': true},
      );

      final body = resp.data as ResponseBody;
      final buffer = StringBuffer();
      await for (final line in body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final l = line.trim();
        if (l.isEmpty || !l.startsWith('data:')) continue;
        final data = l.substring(5).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data);
          final delta = json['choices']?[0]?['delta']?['content'];
          if (delta is String && delta.isNotEmpty) {
            buffer.write(delta);
            onDelta(delta);
          }
        } catch (_) {
          // Ignore keep-alive / non-JSON lines.
        }
      }
      lastModelUsed = resolved;
      final full = buffer.toString().trim();
      if (full.isEmpty) {
        throw OpenRouterException('The AI returned no readable text.');
      }
      return full;
    } on DioException catch (e) {
      throw _mapDioError(e, resolved);
    } catch (e) {
      if (e is OpenRouterException) rethrow;
      throw OpenRouterException('AI stream failed: $e');
    }
  }

  /// Managed backend proxy (`/ai/chat`): no API key; server holds the key and
  /// meters free usage. Content is flattened to text (proxy is text-focused).
  Future<String> _doManagedChat(List<Map<String, dynamic>> messages) async {
    final settings = AppSettings.instance;
    final endpoint = settings.aiEndpoint;
    final flat = messages.map((m) {
      final c = m['content'];
      String text;
      if (c is String) {
        text = c;
      } else if (c is List) {
        text = c
            .whereType<Map>()
            .where((p) => p['type'] == 'text')
            .map((p) => p['text']?.toString() ?? '')
            .join('\n');
      } else {
        text = c?.toString() ?? '';
      }
      return {'role': m['role'] ?? 'user', 'content': text};
    }).toList();

    final headers = <String, dynamic>{'Content-Type': 'application/json'};
    final proToken = settings.proToken;
    if (proToken != null && proToken.isNotEmpty) {
      headers['X-Entitlement-Token'] = proToken; // unlimited for verified Pro
    }
    try {
      final resp = await _dio.post(
        endpoint,
        options: Options(headers: headers),
        data: {'messages': flat, 'use_advanced': false},
      );
      final data = resp.data;
      final reply = (data is Map) ? data['reply']?.toString() : null;
      if (reply == null || reply.trim().isEmpty) {
        throw OpenRouterException('The AI returned no readable text.');
      }
      return reply.trim();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 429) {
        throw OpenRouterException(
            'Daily free AI limit reached. Upgrade to Pro for unlimited AI.');
      }
      if (code == 503) {
        throw OpenRouterException('Managed AI is not set up on the server yet.');
      }
      throw _mapDioError(e, 'managed');
    } catch (e) {
      if (e is OpenRouterException) rethrow;
      throw OpenRouterException('AI request failed: $e');
    }
  }

  Future<String> _doChat(List<Map<String, dynamic>> messages, String model) async {
    final settings = AppSettings.instance;
    final endpoint = settings.aiEndpoint;
    final anthropic = settings.isAnthropic;
    final key = await settings.apiKey();

    if (settings.needsKey && (key == null || key.isEmpty)) {
      throw OpenRouterException(
        'No API key set for ${settings.provider.label}. Open AI Settings and paste '
        'your key${settings.provider.keysUrl.isNotEmpty ? ' (get one at ${settings.provider.keysUrl})' : ''}.',
      );
    }
    if (endpoint.isEmpty) {
      throw OpenRouterException(
        'No AI endpoint set. In AI Settings, choose a provider or enter your custom server URL.',
      );
    }

    try {
      final Response resp;
      if (anthropic) {
        resp = await _dio.post(
          endpoint,
          options: Options(headers: {
            'x-api-key': key ?? '',
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          }),
          data: _anthropicBody(messages, model),
        );
        return _parseAnthropic(resp.data);
      } else {
        final headers = <String, dynamic>{
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://github.com/ai-pdf',
          'X-Title': 'Pdoczy',
        };
        if (key != null && key.isNotEmpty) headers['Authorization'] = 'Bearer $key';
        resp = await _dio.post(
          endpoint,
          options: Options(headers: headers),
          data: {'model': model, 'messages': messages, 'max_tokens': 4096},
        );
        return _parseOpenAi(resp.data);
      }
    } on DioException catch (e) {
      throw _mapDioError(e, model);
    } catch (e) {
      if (e is OpenRouterException) rethrow;
      throw OpenRouterException('AI request failed: $e');
    }
  }

  // ---- OpenAI-compatible response ----
  String _parseOpenAi(dynamic data) {
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
  }

  // ---- Anthropic request/response ----
  Map<String, dynamic> _anthropicBody(List<Map<String, dynamic>> messages, String model) {
    String? system;
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = m['role'];
      final content = m['content'];
      if (role == 'system') {
        final t = content is String ? content : '';
        system = system == null ? t : '$system\n$t';
        continue;
      }
      final blocks = <Map<String, dynamic>>[];
      if (content is String) {
        blocks.add({'type': 'text', 'text': content});
      } else if (content is List) {
        for (final part in content) {
          if (part is! Map) continue;
          if (part['type'] == 'text') {
            blocks.add({'type': 'text', 'text': part['text'] ?? ''});
          } else if (part['type'] == 'image_url') {
            final url = part['image_url']?['url']?.toString() ?? '';
            final img = _dataUrlToAnthropicImage(url);
            if (img != null) blocks.add(img);
          }
        }
      }
      out.add({'role': role, 'content': blocks});
    }
    final body = <String, dynamic>{'model': model, 'max_tokens': 4096, 'messages': out};
    if (system != null && system.isNotEmpty) body['system'] = system;
    return body;
  }

  Map<String, dynamic>? _dataUrlToAnthropicImage(String dataUrl) {
    final match = RegExp(r'^data:([^;]+);base64,(.*)$', dotAll: true).firstMatch(dataUrl);
    if (match == null) return null;
    return {
      'type': 'image',
      'source': {
        'type': 'base64',
        'media_type': match.group(1),
        'data': match.group(2),
      },
    };
  }

  String _parseAnthropic(dynamic data) {
    final content = (data is Map) ? data['content'] as List? : null;
    if (content == null || content.isEmpty) {
      throw OpenRouterException('The AI returned an empty response. Try again.');
    }
    final text = content
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text']?.toString() ?? '')
        .join('\n')
        .trim();
    if (text.isNotEmpty) return text;
    throw OpenRouterException('The AI returned no readable text.');
  }

  OpenRouterException _mapDioError(DioException e, String model) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return OpenRouterException('Connection timed out. Check your internet and try again.');
      case DioExceptionType.receiveTimeout:
        return OpenRouterException(
            'The AI is taking too long (large document?). Try again or use a faster model.');
      case DioExceptionType.connectionError:
        return OpenRouterException(
            'No internet connection. Check Wi-Fi/mobile data, or switch to an offline endpoint in Settings.');
      default:
        break;
    }
    final code = e.response?.statusCode;
    final body = e.response?.data;
    final detail = (body is Map)
        ? (body['error']?['message']?.toString() ?? body['message']?.toString())
        : null;

    if (code == 401 || code == 403) {
      return OpenRouterException('API key invalid or unauthorized. Check it in AI Settings.');
    }
    if (code == 402) {
      return OpenRouterException(
          'This model ($model) needs credits/billing on your account. Add credit or pick a free model.');
    }
    if (code == 429) {
      return OpenRouterException(
          'Rate limit reached. Wait a minute or switch model/provider in AI Settings.');
    }
    if (code == 400 || code == 404) {
      return OpenRouterException(
          'Model "$model" is not available or does not accept images. Switch model in AI Settings.');
    }
    if (code != null && code >= 500) {
      return OpenRouterException('The AI service is down (error $code). Try again shortly.');
    }
    return OpenRouterException(detail ?? 'Network error. Check your connection and try again.');
  }
}
