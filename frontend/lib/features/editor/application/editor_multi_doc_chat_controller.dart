import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single message in the multi-doc chat (Phase 31).
class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;

  /// Optional: which document(s) the message cites or references.
  final List<ChatCitation> citations;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.citations = const [],
    required this.timestamp,
  });
}

enum ChatRole { user, assistant, system }

/// A citation linking a chat response to a specific document + page.
class ChatCitation {
  /// Display name of the document (e.g. "Contract_v2.pdf").
  final String documentName;

  /// Zero-based page index.
  final int? pageIndex;

  /// The snippet of text from the document the AI used.
  final String? snippet;

  const ChatCitation({
    required this.documentName,
    this.pageIndex,
    this.snippet,
  });
}

/// A document registered as context for the multi-doc chat.
class ChatDocument {
  final String id;
  final String name;
  final String? extractedText;
  final int pageCount;

  const ChatDocument({
    required this.id,
    required this.name,
    this.extractedText,
    this.pageCount = 1,
  });
}

/// UI state for the multi-document AI chat (Phase 31).
class EditorMultiDocChatState {
  final bool visible;
  final List<ChatDocument> documents;
  final List<ChatMessage> messages;
  final bool loading;
  final String? error;
  final String? sessionId;

  const EditorMultiDocChatState({
    this.visible = false,
    this.documents = const [],
    this.messages = const [],
    this.loading = false,
    this.error,
    this.sessionId,
  });

  bool get hasDocuments => documents.isNotEmpty;
  int get documentCount => documents.length;

  EditorMultiDocChatState copyWith({
    bool? visible,
    List<ChatDocument>? documents,
    List<ChatMessage>? messages,
    bool? loading,
    String? error,
    String? sessionId,
    bool clearError = false,
  }) =>
      EditorMultiDocChatState(
        visible: visible ?? this.visible,
        documents: documents ?? this.documents,
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        sessionId: sessionId ?? this.sessionId,
      );
}

/// Controller for the multi-document AI chat panel (Phase 31).
///
/// Manages chat sessions, document context, message history, and the
/// send/receive lifecycle. The actual AI call is abstracted behind [sendMessage]
/// which the screen wires to the backend `/ai/chat` endpoint — the controller
/// handles optimistic UI (user message appears immediately, loading indicator,
/// assistant message appended on response, error state on failure).
final editorMultiDocChatProvider =
    StateNotifierProvider<EditorMultiDocChatController, EditorMultiDocChatState>(
        (ref) => EditorMultiDocChatController());

class EditorMultiDocChatController
    extends StateNotifier<EditorMultiDocChatState> {
  EditorMultiDocChatController() : super(const EditorMultiDocChatState());

  int _nextId = 1;

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  /// Register a document as context for the chat.
  void addDocument(ChatDocument doc) {
    if (state.documents.any((d) => d.id == doc.id)) return;
    state = state.copyWith(documents: [...state.documents, doc]);
  }

  /// Remove a document from the chat context.
  void removeDocument(String documentId) {
    state = state.copyWith(
      documents: [
        for (final d in state.documents)
          if (d.id != documentId) d,
      ],
    );
  }

  /// Add the user's message and start loading.
  ///
  /// The caller should then fire the actual API call and follow up with
  /// [receiveAssistantMessage] or [receiveError].
  String sendUserMessage(String content) {
    final id = 'msg_${_nextId++}';
    final msg = ChatMessage(
      id: id,
      role: ChatRole.user,
      content: content,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, msg],
      loading: true,
      clearError: true,
    );
    return id;
  }

  /// Append the assistant's response.
  void receiveAssistantMessage(
    String content, {
    List<ChatCitation> citations = const [],
  }) {
    final msg = ChatMessage(
      id: 'msg_${_nextId++}',
      role: ChatRole.assistant,
      content: content,
      citations: citations,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, msg], loading: false);
  }

  /// Record an error response.
  void receiveError(String error) {
    state = state.copyWith(loading: false, error: error);
  }

  /// Start a new session (clears messages, keeps documents).
  void newSession() {
    state = state.copyWith(
      messages: const [],
      sessionId: 'session_${_nextId++}',
      clearError: true,
    );
  }

  /// Clear everything.
  void reset() {
    state = const EditorMultiDocChatState();
    _nextId = 1;
  }
}
