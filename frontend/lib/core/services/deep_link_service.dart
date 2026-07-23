import 'dart:async';

import 'package:flutter/services.dart';

/// Deep link handling service — processes incoming links from:
/// - Share intents (other apps sharing a PDF to this app)
/// - URL scheme (aidocassistant://open?file=...)
/// - App Links / Universal Links (https://aidocassistant.com/share/...)
/// - Signing request links
///
/// Architecture: method channel receives the initial link and a stream of
/// subsequent links. The service exposes a [Stream] that the app's root widget
/// listens to for navigation.
class DeepLinkService {
  static const _channel = MethodChannel('com.aidocassistant.app/deep_link');
  static const _eventChannel = EventChannel('com.aidocassistant.app/deep_link_events');

  final StreamController<DeepLinkEvent> _controller = StreamController.broadcast();

  /// Stream of incoming deep link events.
  Stream<DeepLinkEvent> get events => _controller.stream;

  /// Initialize and start listening for deep links.
  Future<void> initialize() async {
    // Get the initial link (app opened via link).
    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null && initial.isNotEmpty) {
        _controller.add(_parse(initial));
      }
    } on PlatformException {
      // No initial link.
    }

    // Listen for subsequent links (app already open).
    _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is String && event.isNotEmpty) {
        _controller.add(_parse(event));
      }
    });
  }

  /// Parse a URI into a typed event.
  DeepLinkEvent _parse(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return DeepLinkEvent.unknown(uri);

    // aidocassistant://open?file=/path/to/file.pdf
    if (parsed.path == '/open' || parsed.host == 'open') {
      final file = parsed.queryParameters['file'];
      return file != null ? DeepLinkEvent.openFile(file) : DeepLinkEvent.unknown(uri);
    }

    // https://aidocassistant.com/share/{id}
    if (parsed.path.startsWith('/share/')) {
      final id = parsed.pathSegments.last;
      return DeepLinkEvent.sharedDocument(id);
    }

    // https://aidocassistant.com/sign/{token}
    if (parsed.path.startsWith('/sign/')) {
      final token = parsed.pathSegments.last;
      return DeepLinkEvent.signRequest(token);
    }

    return DeepLinkEvent.unknown(uri);
  }

  void dispose() {
    _controller.close();
  }
}

/// Typed deep link events.
sealed class DeepLinkEvent {
  const DeepLinkEvent();

  factory DeepLinkEvent.openFile(String path) = OpenFileLink;
  factory DeepLinkEvent.sharedDocument(String id) = SharedDocumentLink;
  factory DeepLinkEvent.signRequest(String token) = SignRequestLink;
  factory DeepLinkEvent.unknown(String raw) = UnknownLink;
}

class OpenFileLink extends DeepLinkEvent {
  final String path;
  const OpenFileLink(this.path);
}

class SharedDocumentLink extends DeepLinkEvent {
  final String documentId;
  const SharedDocumentLink(this.documentId);
}

class SignRequestLink extends DeepLinkEvent {
  final String token;
  const SignRequestLink(this.token);
}

class UnknownLink extends DeepLinkEvent {
  final String raw;
  const UnknownLink(this.raw);
}
