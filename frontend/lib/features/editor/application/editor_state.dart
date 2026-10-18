/// Marks a nullable [EditorState.copyWith] argument that was not passed.
class _Keep {
  const _Keep();
}

const _keep = _Keep();

class EditorState {
  final bool loading;
  final bool exporting;
  final int currentPage;
  final int pageCount;
  final bool hasUnsavedChanges;
  final String? filePath;
  final String? fileName;
  final String? error;

  const EditorState({
    this.loading = false,
    this.exporting = false,
    this.currentPage = 0,
    this.pageCount = 0,
    this.hasUnsavedChanges = false,
    this.filePath,
    this.fileName,
    this.error,
  });

  /// Omitting [filePath], [fileName] or [error] keeps the current value;
  /// passing null clears it. (`error ?? this.error` could never clear a stale
  /// error, so `beginExport` and a successful `finishExport` kept showing the
  /// previous failure.)
  EditorState copyWith({
    bool? loading,
    bool? exporting,
    int? currentPage,
    int? pageCount,
    bool? hasUnsavedChanges,
    Object? filePath = _keep,
    Object? fileName = _keep,
    Object? error = _keep,
  }) {
    return EditorState(
      loading: loading ?? this.loading,
      exporting: exporting ?? this.exporting,
      currentPage: currentPage ?? this.currentPage,
      pageCount: pageCount ?? this.pageCount,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      filePath: identical(filePath, _keep) ? this.filePath : filePath as String?,
      fileName: identical(fileName, _keep) ? this.fileName : fileName as String?,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}
