import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Summary length preference (Phase 50).
enum SummaryLength { brief, standard, detailed }

/// A generated summary section (Phase 50).
class SummarySection {
  final String heading;
  final String content;
  final int? pageStart;
  final int? pageEnd;

  const SummarySection({
    required this.heading,
    required this.content,
    this.pageStart,
    this.pageEnd,
  });
}

/// UI state for the AI document summarizer (Phase 50).
class EditorSummarizerState {
  final bool visible;
  final bool generating;
  final SummaryLength length;
  final String? fullSummary;
  final List<SummarySection> sections;
  final List<String> keyPoints;
  final String? error;
  final DateTime? generatedAt;

  const EditorSummarizerState({
    this.visible = false,
    this.generating = false,
    this.length = SummaryLength.standard,
    this.fullSummary,
    this.sections = const [],
    this.keyPoints = const [],
    this.error,
    this.generatedAt,
  });

  bool get hasSummary => fullSummary != null && fullSummary!.isNotEmpty;
  int get wordCount =>
      hasSummary ? fullSummary!.split(RegExp(r'\s+')).length : 0;

  EditorSummarizerState copyWith({
    bool? visible,
    bool? generating,
    SummaryLength? length,
    String? fullSummary,
    List<SummarySection>? sections,
    List<String>? keyPoints,
    String? error,
    DateTime? generatedAt,
    bool clearError = false,
  }) =>
      EditorSummarizerState(
        visible: visible ?? this.visible,
        generating: generating ?? this.generating,
        length: length ?? this.length,
        fullSummary: fullSummary ?? this.fullSummary,
        sections: sections ?? this.sections,
        keyPoints: keyPoints ?? this.keyPoints,
        error: clearError ? null : (error ?? this.error),
        generatedAt: generatedAt ?? this.generatedAt,
      );
}

/// Controller for the AI document summarizer panel (Phase 50).
///
/// Generates a structured summary of the document: full text summary, key
/// bullet points, and per-section summaries with page ranges. The summary can
/// be regenerated at different lengths (brief / standard / detailed). The
/// actual AI call is delegated to the screen (which talks to the backend
/// /ai/summarize endpoint); this controller manages the UI state.
final editorSummarizerProvider =
    StateNotifierProvider<EditorSummarizerController, EditorSummarizerState>(
        (ref) => EditorSummarizerController());

class EditorSummarizerController
    extends StateNotifier<EditorSummarizerState> {
  EditorSummarizerController() : super(const EditorSummarizerState());

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  void setLength(SummaryLength length) =>
      state = state.copyWith(length: length);

  /// Start generating (the screen fires the API call).
  void beginGenerate() =>
      state = state.copyWith(generating: true, clearError: true);

  /// Set the result from the AI call.
  void setResult({
    required String fullSummary,
    List<SummarySection> sections = const [],
    List<String> keyPoints = const [],
  }) {
    state = state.copyWith(
      generating: false,
      fullSummary: fullSummary,
      sections: sections,
      keyPoints: keyPoints,
      generatedAt: DateTime.now(),
    );
  }

  /// Set an error from the AI call.
  void setError(String error) =>
      state = state.copyWith(generating: false, error: error);

  /// Clear the summary (e.g. when opening a new document).
  void clear() => state = const EditorSummarizerState();
}
