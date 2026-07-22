import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single field proposed by AI fill, with validation state (Phase 33).
class ProposedFieldValue {
  final String fieldId;
  final String label;
  final String proposedValue;
  final FieldAcceptState acceptState;
  final String? validationError;
  final String? validationSuggestion;
  final double confidence;

  const ProposedFieldValue({
    required this.fieldId,
    required this.label,
    required this.proposedValue,
    this.acceptState = FieldAcceptState.pending,
    this.validationError,
    this.validationSuggestion,
    this.confidence = 0.0,
  });

  bool get isValid => validationError == null;
  bool get isAccepted => acceptState == FieldAcceptState.accepted;
  bool get isRejected => acceptState == FieldAcceptState.rejected;
  bool get isPending => acceptState == FieldAcceptState.pending;

  ProposedFieldValue copyWith({
    FieldAcceptState? acceptState,
    String? validationError,
    String? validationSuggestion,
    String? proposedValue,
    bool clearValidation = false,
  }) =>
      ProposedFieldValue(
        fieldId: fieldId,
        label: label,
        proposedValue: proposedValue ?? this.proposedValue,
        acceptState: acceptState ?? this.acceptState,
        validationError: clearValidation ? null : (validationError ?? this.validationError),
        validationSuggestion: clearValidation
            ? null
            : (validationSuggestion ?? this.validationSuggestion),
        confidence: confidence,
      );
}

enum FieldAcceptState { pending, accepted, rejected }

/// UI state for the form review panel (Phase 33).
class EditorFormReviewState {
  final bool visible;
  final List<ProposedFieldValue> fields;
  final bool applying;

  const EditorFormReviewState({
    this.visible = false,
    this.fields = const [],
    this.applying = false,
  });

  int get total => fields.length;
  int get accepted => fields.where((f) => f.isAccepted).length;
  int get rejected => fields.where((f) => f.isRejected).length;
  int get pending => fields.where((f) => f.isPending).length;
  int get invalidCount => fields.where((f) => !f.isValid).length;
  bool get allDecided => pending == 0;
  bool get hasAccepted => accepted > 0;

  EditorFormReviewState copyWith({
    bool? visible,
    List<ProposedFieldValue>? fields,
    bool? applying,
  }) =>
      EditorFormReviewState(
        visible: visible ?? this.visible,
        fields: fields ?? this.fields,
        applying: applying ?? this.applying,
      );
}

/// Controller for the form auto-fill review + apply panel (Phase 33).
///
/// After AI fill proposes field values, this controller holds the proposals and
/// their validation state. The user reviews each field (accept / reject /
/// edit), sees inline validation badges (from FieldValidationService P14), and
/// then applies all accepted values at once to the annotation layer.
final editorFormReviewProvider =
    StateNotifierProvider<EditorFormReviewController, EditorFormReviewState>(
        (ref) => EditorFormReviewController());

class EditorFormReviewController
    extends StateNotifier<EditorFormReviewState> {
  EditorFormReviewController() : super(const EditorFormReviewState());

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);

  /// Load a fresh set of AI-proposed fields for review.
  void loadProposals(List<ProposedFieldValue> fields) {
    state = state.copyWith(visible: true, fields: fields);
  }

  void acceptField(String fieldId) =>
      _setAcceptState(fieldId, FieldAcceptState.accepted);

  void rejectField(String fieldId) =>
      _setAcceptState(fieldId, FieldAcceptState.rejected);

  /// Accept all valid, still-pending fields at once.
  void acceptAllValid() {
    state = state.copyWith(
      fields: [
        for (final f in state.fields)
          if (f.isPending && f.isValid)
            f.copyWith(acceptState: FieldAcceptState.accepted)
          else
            f,
      ],
    );
  }

  /// Reject all still-pending fields.
  void rejectAllPending() {
    state = state.copyWith(
      fields: [
        for (final f in state.fields)
          if (f.isPending) f.copyWith(acceptState: FieldAcceptState.rejected) else f,
      ],
    );
  }

  /// Update a field's proposed value (user edited the suggestion).
  void editFieldValue(String fieldId, String newValue) {
    state = state.copyWith(
      fields: [
        for (final f in state.fields)
          if (f.fieldId == fieldId)
            f.copyWith(proposedValue: newValue, clearValidation: true)
          else
            f,
      ],
    );
  }

  /// Attach validation results to a field (called after inline validation runs).
  void setValidation(String fieldId, {String? error, String? suggestion}) {
    state = state.copyWith(
      fields: [
        for (final f in state.fields)
          if (f.fieldId == fieldId)
            f.copyWith(validationError: error, validationSuggestion: suggestion)
          else
            f,
      ],
    );
  }

  /// Begin the apply phase (returns the accepted field IDs + values).
  List<ProposedFieldValue> beginApply() {
    state = state.copyWith(applying: true);
    return [for (final f in state.fields) if (f.isAccepted) f];
  }

  /// Mark apply complete and close the panel.
  void finishApply() {
    state = const EditorFormReviewState();
  }

  void _setAcceptState(String fieldId, FieldAcceptState st) {
    state = state.copyWith(
      fields: [
        for (final f in state.fields)
          if (f.fieldId == fieldId) f.copyWith(acceptState: st) else f,
      ],
    );
  }
}
