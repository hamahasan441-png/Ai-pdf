import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A named export configuration preset (Phase 41).
class ExportPreset {
  final String id;
  final String name;
  final ExportFormat format;
  final ExportQuality quality;
  final bool flattenAnnotations;
  final bool vectorText;
  final bool includeMetadata;
  final String? pageRange;
  final bool builtIn;

  const ExportPreset({
    required this.id,
    required this.name,
    this.format = ExportFormat.pdf,
    this.quality = ExportQuality.high,
    this.flattenAnnotations = true,
    this.vectorText = true,
    this.includeMetadata = true,
    this.pageRange,
    this.builtIn = false,
  });

  ExportPreset copyWith({
    String? name,
    ExportFormat? format,
    ExportQuality? quality,
    bool? flattenAnnotations,
    bool? vectorText,
    bool? includeMetadata,
    String? pageRange,
  }) =>
      ExportPreset(
        id: id,
        name: name ?? this.name,
        format: format ?? this.format,
        quality: quality ?? this.quality,
        flattenAnnotations: flattenAnnotations ?? this.flattenAnnotations,
        vectorText: vectorText ?? this.vectorText,
        includeMetadata: includeMetadata ?? this.includeMetadata,
        pageRange: pageRange ?? this.pageRange,
        builtIn: builtIn,
      );
}

enum ExportFormat { pdf, png, jpeg, tiff }
enum ExportQuality { high, medium, low }

/// A batch export job item.
class BatchExportItem {
  final String filePath;
  final String fileName;
  final BatchExportStatus status;
  final String? error;

  const BatchExportItem({
    required this.filePath,
    required this.fileName,
    this.status = BatchExportStatus.pending,
    this.error,
  });

  BatchExportItem copyWith({BatchExportStatus? status, String? error}) =>
      BatchExportItem(
        filePath: filePath,
        fileName: fileName,
        status: status ?? this.status,
        error: error ?? this.error,
      );
}

enum BatchExportStatus { pending, running, done, failed }

/// UI state for export presets + batch export (Phase 41).
class EditorExportPresetsState {
  final bool visible;
  final List<ExportPreset> presets;
  final ExportPreset? selectedPreset;
  final List<BatchExportItem> batchItems;
  final bool batchRunning;

  const EditorExportPresetsState({
    this.visible = false,
    this.presets = const [],
    this.selectedPreset,
    this.batchItems = const [],
    this.batchRunning = false,
  });

  int get batchTotal => batchItems.length;
  int get batchDone =>
      batchItems.where((i) => i.status == BatchExportStatus.done).length;
  int get batchFailed =>
      batchItems.where((i) => i.status == BatchExportStatus.failed).length;
  double get batchProgress =>
      batchTotal == 0 ? 0 : (batchDone + batchFailed) / batchTotal;
  bool get isBatchComplete => batchDone + batchFailed == batchTotal && batchTotal > 0;

  EditorExportPresetsState copyWith({
    bool? visible,
    List<ExportPreset>? presets,
    ExportPreset? selectedPreset,
    List<BatchExportItem>? batchItems,
    bool? batchRunning,
    bool clearSelection = false,
  }) =>
      EditorExportPresetsState(
        visible: visible ?? this.visible,
        presets: presets ?? this.presets,
        selectedPreset: clearSelection ? null : (selectedPreset ?? this.selectedPreset),
        batchItems: batchItems ?? this.batchItems,
        batchRunning: batchRunning ?? this.batchRunning,
      );
}

/// Controller for export presets + batch export (Phase 41).
///
/// Manages named export configurations (format, quality, flatten, page range)
/// so the user can export with one tap. Also drives batch export: apply a
/// preset to multiple files sequentially with progress tracking.
final editorExportPresetsProvider =
    StateNotifierProvider<EditorExportPresetsController, EditorExportPresetsState>(
        (ref) => EditorExportPresetsController());

class EditorExportPresetsController
    extends StateNotifier<EditorExportPresetsState> {
  EditorExportPresetsController() : super(const EditorExportPresetsState()) {
    _loadBuiltIns();
  }

  int _nextId = 1;

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);

  void selectPreset(ExportPreset? preset) =>
      state = state.copyWith(selectedPreset: preset, clearSelection: preset == null);

  ExportPreset savePreset({
    required String name,
    ExportFormat format = ExportFormat.pdf,
    ExportQuality quality = ExportQuality.high,
    bool flattenAnnotations = true,
    bool vectorText = true,
    bool includeMetadata = true,
    String? pageRange,
  }) {
    final preset = ExportPreset(
      id: 'preset_${_nextId++}',
      name: name,
      format: format,
      quality: quality,
      flattenAnnotations: flattenAnnotations,
      vectorText: vectorText,
      includeMetadata: includeMetadata,
      pageRange: pageRange,
    );
    state = state.copyWith(presets: [...state.presets, preset]);
    return preset;
  }

  void deletePreset(String id) {
    state = state.copyWith(
      presets: [for (final p in state.presets) if (p.id != id || p.builtIn) p],
    );
  }

  /// Start a batch export with the given file paths.
  void startBatch(List<String> filePaths) {
    final items = [
      for (final fp in filePaths)
        BatchExportItem(filePath: fp, fileName: fp.split('/').last),
    ];
    state = state.copyWith(batchItems: items, batchRunning: true);
  }

  /// Mark a batch item as running.
  void markRunning(int index) => _updateBatch(index, BatchExportStatus.running);

  /// Mark a batch item as done.
  void markDone(int index) => _updateBatch(index, BatchExportStatus.done);

  /// Mark a batch item as failed.
  void markFailed(int index, String error) {
    final items = [...state.batchItems];
    items[index] = items[index].copyWith(status: BatchExportStatus.failed, error: error);
    final allDone = items.every((i) =>
        i.status == BatchExportStatus.done || i.status == BatchExportStatus.failed);
    state = state.copyWith(batchItems: items, batchRunning: !allDone);
  }

  void clearBatch() =>
      state = state.copyWith(batchItems: const [], batchRunning: false);

  void _updateBatch(int index, BatchExportStatus status) {
    final items = [...state.batchItems];
    items[index] = items[index].copyWith(status: status);
    final allDone = items.every((i) =>
        i.status == BatchExportStatus.done || i.status == BatchExportStatus.failed);
    state = state.copyWith(batchItems: items, batchRunning: !allDone);
  }

  void _loadBuiltIns() {
    final builtIns = [
      const ExportPreset(
        id: 'builtin_hq_pdf',
        name: 'High Quality PDF',
        format: ExportFormat.pdf,
        quality: ExportQuality.high,
        builtIn: true,
      ),
      const ExportPreset(
        id: 'builtin_web_pdf',
        name: 'Web-optimized PDF',
        format: ExportFormat.pdf,
        quality: ExportQuality.medium,
        builtIn: true,
      ),
      const ExportPreset(
        id: 'builtin_png',
        name: 'PNG per page',
        format: ExportFormat.png,
        quality: ExportQuality.high,
        flattenAnnotations: true,
        builtIn: true,
      ),
    ];
    state = state.copyWith(presets: [...builtIns]);
  }
}
