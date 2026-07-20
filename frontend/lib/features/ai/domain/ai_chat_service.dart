import 'package:ai_pdf/core/services/bm25_retriever.dart';

/// Message in a conversation.
class ChatMessage {
  final String role;    // 'user' | 'assistant' | 'system'
  final String content;
  final DateTime timestamp;
  final List<int>? citedPages; // pages the answer was grounded on

  const ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.citedPages,
  }) : timestamp = timestamp ?? const _Now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'citedPages': citedPages,
      };
}

class _Now implements DateTime {
  const _Now();
  @override dynamic noSuchMethod(Invocation i) => DateTime.now().noSuchMethod(i);
}

/// A conversation session with one document.
class ChatSession {
  final String id;
  final String documentName;
  final List<ChatMessage> messages = [];
  final Bm25Retriever retriever = Bm25Retriever();
  DateTime lastActive;
  int pageCount;

  ChatSession({
    required this.id,
    required this.documentName,
    DateTime? lastActive,
    this.pageCount = 0,
  }) : lastActive = lastActive ?? DateTime.now();

  bool get isIndexed => retriever.chunkCount > 0;

  /// Index the OCR'd text per page for RAG retrieval.
  void indexPages(Map<int, String> pageText) {
    retriever.index(pageText);
    pageCount = pageText.length;
  }

  /// Retrieve the most relevant passages for a query.
  List<RetrievedChunk> retrieve(String query, {int topK = 5}) {
    return retriever.search(query, topK: topK);
  }

  /// Build the grounded system prompt including retrieved context.
  String buildSystemPrompt({
    required String basePrompt,
    required List<RetrievedChunk> chunks,
  }) {
    if (chunks.isEmpty) {
      return '$basePrompt\n\nDocument: $documentName ($pageCount pages).\n'
          'The user may ask questions about this document. Answer based on the content.';
    }
    final contextLines = chunks.map((c) => '[Page ${c.page}] ${c.text}').join('\n---\n');
    return '$basePrompt\n\n'
        'Document: $documentName ($pageCount pages).\n\n'
        'Relevant excerpts (cite the page number when answering):\n$contextLines\n\n'
        'Answer based ONLY on the above context. If the answer is not in the context, say so.';
  }

  void addMessage(ChatMessage msg) {
    messages.add(msg);
    lastActive = DateTime.now();
  }
}

/// Prompt templates for different AI modes.
class AiPrompts {
  static const summarize =
      'You are a document summarizer. Provide a structured summary with: '
      '1. Document type & purpose, 2. Key points (bullet list), '
      '3. Important dates/amounts/names, 4. Action items if any. '
      'Be concise and factual.';

  static const chatWithPdf =
      'You are a helpful document assistant. Answer questions about the document '
      'accurately and cite the page number. If the answer is not in the provided context, '
      'say "I could not find this information in the document."';

  static const translate =
      'You are a professional translator. Translate the following text accurately, '
      'preserving meaning, tone, and formatting. Do not add commentary.';

  static const rewrite =
      'You are a professional editor. Rewrite the following text to improve clarity, '
      'grammar, and readability while preserving the original meaning.';

  static const extractData =
      'You are a data extraction expert. Extract ALL structured data from this document '
      'and return it as a clean JSON object with meaningful keys.';

  static const fixOcr =
      'You are an OCR error corrector. Fix common OCR mistakes in this text: '
      'wrong characters (rn→m, l→1, O→0), missing spaces, broken words, garbled Unicode. '
      'Return the corrected text only.';
}
