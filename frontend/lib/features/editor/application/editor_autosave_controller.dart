import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recovery entry for a previously unsaved session (Phase 39).
class RecoveryEntry {
  final String id;
  final String fileName;
  final String filePath;
  final DateTime savedAt;
  final int pageCount;
  final int annotationCount;

  const RecoveryEntry({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.savedAt,
    required this.pageCount,
    required this.annotationCount,
  });
}

/// UI state for the auto-save & crash recovery system (Phase 39).
class EditorAutosaveState {
  final bool enabled;
  final int intervalSeconds;
  final DateTime? lastSaveAt;
  final bool saving;
  final String? lastError;
  final List<RecoveryEntry> recoveryEntries;
  final bool showRecoveryDialog;

  const EditorAutosaveState({
    this.enabled = true,
    this.intervalSeconds = 30,
    this.lastSaveAt,
    this.saving = false,
    this.lastError,
    this.recoveryEntries = const [],
    this.showRecoveryDialog = false,
  });

  bool get hasRecovery => recoveryEntries.isNotEmpty;
  String get statusLabel {
    if (!enabled) return 'Auto-save off';
    if (saving) return 'Saving...';
    if (lastSaveAt != null) {
      final ago = DateTime.now().difference(lastSaveAt!).inSeconds;
      if (ago < 60) return 'Saved ${ago}s ago';
      return 'Saved ${ago ~/ 60}m ago';
    }
    return 'Auto-save on';
  }

  EditorAutosaveState copyWith({
    bool? enabled,
    int? intervalSeconds,
    DateTime? lastSaveAt,
    bool? saving,
    String? lastError,
    List<RecoveryEntry>? recoveryEntries,
    bool? showRecoveryDialog,
    bool clearError = false,
  }) =>
      EditorAutosaveState(
        enabled: enabled ?? this.enabled,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
        lastSaveAt: lastSaveAt ?? this.lastSaveAt,
        saving: saving ?? this.saving,
        lastError: clearError ? null : (lastError ?? this.lastError),
        recoveryEntries: recoveryEntries ?? this.recoveryEntries,
        showRecoveryDialog: showRecoveryDialog ?? this.showRecoveryDialog,
      );
}

/// Controller for auto-save & crash recovery (Phase 39).
///
/// Periodically persists the annotation state (via AnnotationPersistenceService)
/// so unsaved work survives app crashes, background kills, and accidental exits.
/// On next app launch, if recovery data is found, shows a dialog offering to
/// restore the session.
final editorAutosaveProvider =
    StateNotifierProvider<EditorAutosaveController, EditorAutosaveState>(
        (ref) => EditorAutosaveController());

class EditorAutosaveController extends StateNotifier<EditorAutosaveState> {
  EditorAutosaveController() : super(const EditorAutosaveState());

  void setEnabled(bool value) => state = state.copyWith(enabled: value);

  void setInterval(int seconds) =>
      state = state.copyWith(intervalSeconds: seconds.clamp(10, 300));

  /// Called when a save starts.
  void beginSave() => state = state.copyWith(saving: true, clearError: true);

  /// Called when the save succeeds.
  void completeSave() =>
      state = state.copyWith(saving: false, lastSaveAt: DateTime.now());

  /// Called when the save fails.
  void failSave(String error) =>
      state = state.copyWith(saving: false, lastError: error);

  /// Load recovery entries (called on app start before opening a new document).
  void loadRecoveryEntries(List<RecoveryEntry> entries) {
    state = state.copyWith(
      recoveryEntries: entries,
      showRecoveryDialog: entries.isNotEmpty,
    );
  }

  /// User chose to recover a session.
  RecoveryEntry? acceptRecovery(String entryId) {
    final entry = state.recoveryEntries
        .cast<RecoveryEntry?>()
        .firstWhere((e) => e?.id == entryId, orElse: () => null);
    state = state.copyWith(showRecoveryDialog: false);
    return entry;
  }

  /// User dismissed the recovery dialog (discard all).
  void dismissRecovery() {
    state = state.copyWith(
      recoveryEntries: const [],
      showRecoveryDialog: false,
    );
  }

  /// Delete a specific recovery entry.
  void deleteEntry(String entryId) {
    state = state.copyWith(
      recoveryEntries: [
        for (final e in state.recoveryEntries)
          if (e.id != entryId) e,
      ],
    );
  }

  void reset() => state = const EditorAutosaveState();
}
