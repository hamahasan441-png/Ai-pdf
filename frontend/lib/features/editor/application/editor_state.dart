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

  EditorState copyWith({
    bool? loading,
    bool? exporting,
    int? currentPage,
    int? pageCount,
    bool? hasUnsavedChanges,
    String? filePath,
    String? fileName,
    String? error,
  }) {
    return EditorState(
      loading: loading ?? this.loading,
      exporting: exporting ?? this.exporting,
      currentPage: currentPage ?? this.currentPage,
      pageCount: pageCount ?? this.pageCount,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      error: error ?? this.error,
    );
  }
}
