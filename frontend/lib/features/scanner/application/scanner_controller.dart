import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_filter.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_page.dart';

/// Which stage of the scan flow the UI is in.
enum ScanStage {
  /// Live camera / capture screen.
  capturing,

  /// Adjusting the detected corners of the just-captured page.
  cropping,

  /// Reviewing all captured pages (grid) before export.
  reviewing,

  /// Text detection / OCR processing stage.
  textDetection,
}

/// UI state for a scan session (Phase 51).
class ScannerState {
  final List<ScanPage> pages;
  final ScanStage stage;

  /// The page currently being cropped/edited (index into [pages]), or null.
  final int? activeIndex;

  final bool autoCapture;
  final ScanFilter defaultFilter;
  final bool exporting;
  final String? error;

  /// Combined OCR text from all pages (aggregated after detection).
  final String recognizedText;

  /// Current page index being OCR'd (for progress display), -1 if idle.
  final int ocrProgressIndex;

  /// Whether the searchable PDF option is enabled.
  final bool searchablePdf;

  const ScannerState({
    this.pages = const [],
    this.stage = ScanStage.capturing,
    this.activeIndex,
    this.autoCapture = true,
    this.defaultFilter = ScanFilter.auto,
    this.exporting = false,
    this.error,
    this.recognizedText = '',
    this.ocrProgressIndex = -1,
    this.searchablePdf = true,
  });

  int get pageCount => pages.length;
  bool get hasPages => pages.isNotEmpty;
  bool get isOcrRunning => ocrProgressIndex >= 0;

  ScanPage? get activePage =>
      (activeIndex != null && activeIndex! >= 0 && activeIndex! < pages.length)
          ? pages[activeIndex!]
          : null;

  ScannerState copyWith({
    List<ScanPage>? pages,
    ScanStage? stage,
    int? activeIndex,
    bool? autoCapture,
    ScanFilter? defaultFilter,
    bool? exporting,
    String? error,
    String? recognizedText,
    int? ocrProgressIndex,
    bool? searchablePdf,
    bool clearActive = false,
    bool clearError = false,
  }) {
    return ScannerState(
      pages: pages ?? this.pages,
      stage: stage ?? this.stage,
      activeIndex: clearActive ? null : (activeIndex ?? this.activeIndex),
      autoCapture: autoCapture ?? this.autoCapture,
      defaultFilter: defaultFilter ?? this.defaultFilter,
      exporting: exporting ?? this.exporting,
      error: clearError ? null : (error ?? this.error),
      recognizedText: recognizedText ?? this.recognizedText,
      ocrProgressIndex: ocrProgressIndex ?? this.ocrProgressIndex,
      searchablePdf: searchablePdf ?? this.searchablePdf,
    );
  }
}

/// Controller orchestrating the scan session (Phase 51).
///
/// Owns the page list and flow stage. Heavy pixel work (dewarp + filter) is
/// delegated to the screen (which runs [ScanImageProcessor] in a background
/// isolate) and reported back via [markProcessing] / [setProcessed]; this keeps
/// the controller pure and testable.
final scannerControllerProvider =
    StateNotifierProvider<ScannerController, ScannerState>(
        (ref) => ScannerController());

class ScannerController extends StateNotifier<ScannerState> {
  ScannerController() : super(const ScannerState());

  int _seq = 1;

  /// Add a freshly captured page and jump into crop mode for it.
  ScanPage addCapture(Uint8List originalBytes, DocumentCorners corners) {
    final page = ScanPage(
      id: 'scan_${_seq++}',
      originalBytes: originalBytes,
      corners: corners,
      filter: state.defaultFilter,
    );
    final pages = [...state.pages, page];
    state = state.copyWith(
      pages: pages,
      activeIndex: pages.length - 1,
      stage: ScanStage.cropping,
      clearError: true,
    );
    return page;
  }

  /// Update the corners of the active (or given) page and invalidate its
  /// processed output so it re-renders.
  void updateCorners(DocumentCorners corners, {String? pageId}) {
    _mutate(pageId, (p) => p.copyWith(corners: corners, clearProcessed: true));
  }

  /// Change the filter for a page (invalidates processed output).
  void setFilter(ScanFilter filter, {String? pageId}) {
    _mutate(pageId, (p) => p.copyWith(filter: filter, clearProcessed: true));
    if (pageId == null && state.activePage == null) {
      state = state.copyWith(defaultFilter: filter);
    }
  }

  /// Set the default filter applied to newly captured pages.
  void setDefaultFilter(ScanFilter filter) =>
      state = state.copyWith(defaultFilter: filter);

  /// Rotate a page 90° clockwise.
  void rotatePage({String? pageId}) => _mutate(pageId, (p) => p.rotatedCW());

  /// Mark a page as (re)processing.
  void markProcessing(String pageId, bool value) =>
      _mutate(pageId, (p) => p.copyWith(processing: value));

  /// Store the processed (dewarped + filtered) bytes for a page.
  void setProcessed(String pageId, Uint8List bytes) => _mutate(
      pageId, (p) => p.copyWith(processedBytes: bytes, processing: false));

  /// Delete a page. Adjusts the active index / stage as needed.
  void deletePage(String pageId) {
    final pages = [
      for (final p in state.pages)
        if (p.id != pageId) p,
    ];
    state = state.copyWith(
      pages: pages,
      clearActive: true,
      stage: pages.isEmpty ? ScanStage.capturing : state.stage,
    );
  }

  /// Reorder pages (drag in the review grid).
  void reorderPages(int oldIndex, int newIndex) {
    final pages = [...state.pages];
    final item = pages.removeAt(oldIndex);
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    pages.insert(adjusted, item);
    state = state.copyWith(pages: pages);
  }

  /// Enter crop mode for an existing page.
  void editPage(String pageId) {
    final idx = state.pages.indexWhere((p) => p.id == pageId);
    if (idx < 0) return;
    state = state.copyWith(activeIndex: idx, stage: ScanStage.cropping);
  }

  /// Confirm the current crop and move to the review grid.
  void confirmCrop() =>
      state = state.copyWith(stage: ScanStage.reviewing, clearActive: true);

  /// Go back to the capture screen (to add another page).
  void resumeCapture() =>
      state = state.copyWith(stage: ScanStage.capturing, clearActive: true);

  void goToReview() =>
      state = state.copyWith(stage: ScanStage.reviewing, clearActive: true);

  /// Enter the text detection stage.
  void goToTextDetection() =>
      state = state.copyWith(stage: ScanStage.textDetection, clearActive: true);

  /// Set OCR progress (which page index is currently being processed).
  void setOcrProgress(int index) =>
      state = state.copyWith(ocrProgressIndex: index);

  /// Store OCR text for a specific page.
  void setPageOcrText(String pageId, String text) {
    _mutate(pageId, (p) => p.copyWith(extractedText: text, ocrProcessing: false));
    // Rebuild the combined recognized text.
    _rebuildRecognizedText();
  }

  /// Mark a page as currently running OCR.
  void markOcrProcessing(String pageId, bool value) =>
      _mutate(pageId, (p) => p.copyWith(ocrProcessing: value));

  /// Clear all OCR results.
  void clearOcr() {
    state = state.copyWith(
      pages: [
        for (final p in state.pages) p.copyWith(clearOcrText: true),
      ],
      recognizedText: '',
      ocrProgressIndex: -1,
    );
  }

  /// Finish OCR processing (reset progress index).
  void finishOcr() => state = state.copyWith(ocrProgressIndex: -1);

  /// Toggle searchable PDF mode.
  void toggleSearchablePdf() =>
      state = state.copyWith(searchablePdf: !state.searchablePdf);

  void _rebuildRecognizedText() {
    final buf = StringBuffer();
    for (var i = 0; i < state.pages.length; i++) {
      final text = state.pages[i].extractedText;
      if (text != null && text.isNotEmpty) {
        if (buf.isNotEmpty) buf.write('\n\n');
        buf.write('--- Page ${i + 1} ---\n$text');
      }
    }
    state = state.copyWith(recognizedText: buf.toString());
  }

  void toggleAutoCapture() =>
      state = state.copyWith(autoCapture: !state.autoCapture);

  void beginExport() => state = state.copyWith(exporting: true, clearError: true);
  void finishExport() => state = state.copyWith(exporting: false);
  void setError(String message) =>
      state = state.copyWith(error: message, exporting: false);

  /// Clear the whole session.
  void reset() {
    state = const ScannerState();
    _seq = 1;
  }

  void _mutate(String? pageId, ScanPage Function(ScanPage) transform) {
    final id = pageId ?? state.activePage?.id;
    if (id == null) return;
    state = state.copyWith(
      pages: [
        for (final p in state.pages)
          if (p.id == id) transform(p) else p,
      ],
    );
  }
}
