import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:ai_pdf/features/scanner/application/scanner_controller.dart';
import 'package:ai_pdf/features/scanner/data/scan_image_processor.dart';
import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_filter.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_page.dart';
import 'package:ai_pdf/features/scanner/domain/services/document_detection_service.dart';
import 'package:ai_pdf/features/scanner/presentation/widgets/scan_crop_editor.dart';
import 'package:ai_pdf/features/scanner/presentation/widgets/scan_filter_bar.dart';
import 'package:ai_pdf/features/scanner/presentation/widgets/scan_review_grid.dart';

/// Isolate-sendable job describing one page's dewarp + filter.
class ScanProcessJob {
  final Uint8List bytes;
  final List<double> cornerCoords; // [tlx,tly,trx,try,brx,bry,blx,bly]
  final int filterIndex;
  final int rotationQuarterTurns;

  const ScanProcessJob({
    required this.bytes,
    required this.cornerCoords,
    required this.filterIndex,
    required this.rotationQuarterTurns,
  });
}

/// Top-level entry for `compute` — dewarps and filters one page off the UI
/// thread. Returns processed JPEG bytes (or null on failure).
Uint8List? runScanProcessJob(ScanProcessJob job) {
  final c = job.cornerCoords;
  final corners = DocumentCorners(
    topLeft: ui.Offset(c[0], c[1]),
    topRight: ui.Offset(c[2], c[3]),
    bottomRight: ui.Offset(c[4], c[5]),
    bottomLeft: ui.Offset(c[6], c[7]),
  );
  return const ScanImageProcessor().process(
    sourceBytes: job.bytes,
    corners: corners,
    filter: ScanFilter.values[job.filterIndex],
    rotationQuarterTurns: job.rotationQuarterTurns,
  );
}

/// The professional document scanner screen (Phase 51).
///
/// Flow: capture (system camera) -> auto edge-detect + crop editor -> filter
/// -> review grid (reorder / rotate / delete) -> export multi-page PDF.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  static const _detector = DocumentDetectionService();
  static const _processor = ScanImageProcessor();

  /// Original-image pixel sizes keyed by page id (for the crop editor mapping).
  final Map<String, ui.Size> _sizes = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_titleFor(state.stage)),
        actions: [
          if (state.hasPages && state.stage != ScanStage.reviewing)
            TextButton.icon(
              icon: const Icon(Icons.grid_view, color: Colors.white),
              label: Text('${state.pageCount}',
                  style: const TextStyle(color: Colors.white)),
              onPressed: () =>
                  ref.read(scannerControllerProvider.notifier).goToReview(),
            ),
        ],
      ),
      body: switch (state.stage) {
        ScanStage.capturing => _captureView(state),
        ScanStage.cropping => _cropView(state),
        ScanStage.reviewing => _reviewView(state),
      },
    );
  }

  String _titleFor(ScanStage stage) => switch (stage) {
        ScanStage.capturing => 'Scan Document',
        ScanStage.cropping => 'Adjust Edges',
        ScanStage.reviewing => 'Review & Export',
      };

  // ── Capture ──────────────────────────────────────────────────────────────

  Widget _captureView(ScannerState state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.document_scanner_outlined,
              size: 96, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'Point your camera at a document',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: Text(state.hasPages ? 'Capture next page' : 'Capture'),
            onPressed: _capture,
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.photo_library_outlined, color: Colors.white70),
            label: const Text('Import from gallery',
                style: TextStyle(color: Colors.white70)),
            onPressed: _importFromGallery,
          ),
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Text(state.error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }

  Future<void> _capture() => _pick(ImageSource.camera);
  Future<void> _importFromGallery() => _pick(ImageSource.gallery);

  Future<void> _pick(ImageSource source) async {
    final controller = ref.read(scannerControllerProvider.notifier);
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 100,
        maxWidth: 3000,
        maxHeight: 3000,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();

      // Auto-detect the document boundary from a downscaled analysis pass.
      final input = _processor.extractDetectionInput(bytes);
      final DocumentCorners corners;
      final ui.Size size;
      if (input == null) {
        size = const ui.Size(1000, 1400);
        corners = DocumentCorners.insetFrame(size, 0.05);
      } else {
        size = input.fullSize;
        final result = _detector.estimateFromEnergy(
          input.rowEnergy,
          input.colEnergy,
          input.fullSize,
        );
        corners = result.corners;
      }

      final page = controller.addCapture(bytes, corners);
      _sizes[page.id] = size;
      // Kick off processing for the thumbnail.
      _process(page.id);
    } catch (e) {
      controller.setError('Capture failed: $e');
    }
  }

  // ── Crop ─────────────────────────────────────────────────────────────────

  Widget _cropView(ScannerState state) {
    final page = state.activePage;
    if (page == null) {
      return const Center(
          child: Text('No page', style: TextStyle(color: Colors.white)));
    }
    final size = _sizes[page.id] ?? const ui.Size(1000, 1400);
    return Column(
      children: [
        Expanded(
          child: ScanCropEditor(
            imageBytes: page.originalBytes,
            imageSize: size,
            corners: page.corners,
            onCornersChanged: (c) => ref
                .read(scannerControllerProvider.notifier)
                .updateCorners(c, pageId: page.id),
          ),
        ),
        ScanFilterBar(
          selected: page.filter,
          onSelected: (f) => ref
              .read(scannerControllerProvider.notifier)
              .setFilter(f, pageId: page.id),
        ),
        _cropActions(page),
      ],
    );
  }

  Widget _cropActions(ScanPage page) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.rotate_right, color: Colors.white),
              onPressed: () => ref
                  .read(scannerControllerProvider.notifier)
                  .rotatePage(pageId: page.id),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                await _process(page.id);
                ref.read(scannerControllerProvider.notifier).confirmCrop();
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Review ─────────────────────────────────────────────────────────────

  Widget _reviewView(ScannerState state) {
    final controller = ref.read(scannerControllerProvider.notifier);
    return Column(
      children: [
        Expanded(
          child: state.hasPages
              ? ScanReviewGrid(
                  pages: state.pages,
                  onEdit: controller.editPage,
                  onRotate: (id) async {
                    controller.rotatePage(pageId: id);
                    await _process(id);
                  },
                  onDelete: controller.deletePage,
                  onReorder: controller.reorderPages,
                )
              : const Center(
                  child: Text('No pages yet',
                      style: TextStyle(color: Colors.white70)),
                ),
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.all(12),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo, color: Colors.white),
                  label: const Text('Add page',
                      style: TextStyle(color: Colors.white)),
                  onPressed: controller.resumeCapture,
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: state.exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                  onPressed:
                      state.exporting || !state.hasPages ? null : _exportPdf,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Processing & export ──────────────────────────────────────────────────

  Future<void> _process(String pageId) async {
    final controller = ref.read(scannerControllerProvider.notifier);
    final state = ref.read(scannerControllerProvider);
    final page = state.pages.cast<ScanPage?>().firstWhere(
        (p) => p?.id == pageId,
        orElse: () => null);
    if (page == null) return;

    controller.markProcessing(pageId, true);
    final c = page.corners;
    final job = ScanProcessJob(
      bytes: page.originalBytes,
      cornerCoords: [
        c.topLeft.dx, c.topLeft.dy,
        c.topRight.dx, c.topRight.dy,
        c.bottomRight.dx, c.bottomRight.dy,
        c.bottomLeft.dx, c.bottomLeft.dy,
      ],
      filterIndex: page.filter.index,
      rotationQuarterTurns: page.rotationQuarterTurns,
    );
    try {
      final result = await compute(runScanProcessJob, job);
      if (result != null) {
        controller.setProcessed(pageId, result);
      } else {
        controller.markProcessing(pageId, false);
      }
    } catch (e) {
      controller.markProcessing(pageId, false);
      controller.setError('Processing failed: $e');
    }
  }

  Future<void> _exportPdf() async {
    final controller = ref.read(scannerControllerProvider.notifier);
    final state = ref.read(scannerControllerProvider);
    controller.beginExport();
    try {
      final doc = pw.Document();
      for (final page in state.pages) {
        final image = pw.MemoryImage(page.displayBytes);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (_) => pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ),
        );
      }
      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/scan_$ts.pdf';
      final f = File(path);
      await f.writeAsBytes(bytes);
      controller.finishExport();
      await Share.shareXFiles([XFile(path)], text: 'Scanned document');
    } catch (e) {
      controller.setError('Export failed: $e');
    }
  }
}
