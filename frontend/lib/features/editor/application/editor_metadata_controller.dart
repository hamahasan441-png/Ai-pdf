import 'package:flutter_riverpod/flutter_riverpod.dart';

/// PDF document metadata fields (Phase 38).
class DocumentMetadata {
  final String title;
  final String author;
  final String subject;
  final String keywords;
  final String creator;
  final String producer;
  final DateTime? creationDate;
  final DateTime? modificationDate;
  final int pageCount;
  final String? pdfVersion;
  final int? fileSizeBytes;

  const DocumentMetadata({
    this.title = '',
    this.author = '',
    this.subject = '',
    this.keywords = '',
    this.creator = '',
    this.producer = '',
    this.creationDate,
    this.modificationDate,
    this.pageCount = 0,
    this.pdfVersion,
    this.fileSizeBytes,
  });

  /// Formatted file size.
  String get fileSizeFormatted {
    if (fileSizeBytes == null) return '—';
    if (fileSizeBytes! < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes! < 1024 * 1024) {
      return '${(fileSizeBytes! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  DocumentMetadata copyWith({
    String? title,
    String? author,
    String? subject,
    String? keywords,
    String? creator,
    String? producer,
    DateTime? creationDate,
    DateTime? modificationDate,
    int? pageCount,
    String? pdfVersion,
    int? fileSizeBytes,
  }) =>
      DocumentMetadata(
        title: title ?? this.title,
        author: author ?? this.author,
        subject: subject ?? this.subject,
        keywords: keywords ?? this.keywords,
        creator: creator ?? this.creator,
        producer: producer ?? this.producer,
        creationDate: creationDate ?? this.creationDate,
        modificationDate: modificationDate ?? this.modificationDate,
        pageCount: pageCount ?? this.pageCount,
        pdfVersion: pdfVersion ?? this.pdfVersion,
        fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      );
}

/// UI state for the metadata editor (Phase 38).
class EditorMetadataState {
  final bool visible;
  final DocumentMetadata metadata;
  final bool dirty;

  const EditorMetadataState({
    this.visible = false,
    this.metadata = const DocumentMetadata(),
    this.dirty = false,
  });

  EditorMetadataState copyWith({
    bool? visible,
    DocumentMetadata? metadata,
    bool? dirty,
  }) =>
      EditorMetadataState(
        visible: visible ?? this.visible,
        metadata: metadata ?? this.metadata,
        dirty: dirty ?? this.dirty,
      );
}

/// Controller for the document metadata editor (Phase 38).
///
/// Shows and lets the user edit PDF info fields: title, author, subject,
/// keywords, creator, producer. Also displays read-only stats: creation date,
/// modification date, page count, PDF version, file size. The "Save" action
/// embeds the updated metadata into the exported PDF.
final editorMetadataProvider =
    StateNotifierProvider<EditorMetadataController, EditorMetadataState>(
        (ref) => EditorMetadataController());

class EditorMetadataController extends StateNotifier<EditorMetadataState> {
  EditorMetadataController() : super(const EditorMetadataState());

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  /// Load metadata from an opened document.
  void load(DocumentMetadata meta) {
    state = state.copyWith(metadata: meta, dirty: false);
  }

  void setTitle(String value) =>
      state = state.copyWith(metadata: state.metadata.copyWith(title: value), dirty: true);

  void setAuthor(String value) =>
      state = state.copyWith(metadata: state.metadata.copyWith(author: value), dirty: true);

  void setSubject(String value) =>
      state = state.copyWith(metadata: state.metadata.copyWith(subject: value), dirty: true);

  void setKeywords(String value) =>
      state = state.copyWith(metadata: state.metadata.copyWith(keywords: value), dirty: true);

  void setCreator(String value) =>
      state = state.copyWith(metadata: state.metadata.copyWith(creator: value), dirty: true);

  void setProducer(String value) =>
      state = state.copyWith(metadata: state.metadata.copyWith(producer: value), dirty: true);

  /// Get the current metadata for embedding into the exported PDF.
  DocumentMetadata get current => state.metadata;

  /// Clear the dirty flag after saving.
  void markClean() => state = state.copyWith(dirty: false);

  void reset() => state = const EditorMetadataState();
}
