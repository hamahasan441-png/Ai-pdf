import 'dart:ui' show Offset, Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A predefined aspect ratio for the crop tool (Phase 42).
class CropAspectRatio {
  final String label;
  final double? ratio; // null = freeform

  const CropAspectRatio(this.label, this.ratio);

  static const freeform = CropAspectRatio('Free', null);
  static const a4Portrait = CropAspectRatio('A4', 1 / 1.414);
  static const a4Landscape = CropAspectRatio('A4 \u2194', 1.414);
  static const square = CropAspectRatio('1:1', 1.0);
  static const fourThree = CropAspectRatio('4:3', 4 / 3);
  static const sixteenNine = CropAspectRatio('16:9', 16 / 9);

  static const presets = [freeform, a4Portrait, a4Landscape, square, fourThree, sixteenNine];
}

/// UI state for the crop/margin tool (Phase 42).
class EditorCropState {
  final bool active;

  /// The current crop rect in normalised 0..1 page space.
  final Rect cropRect;

  /// Which handle (if any) the user is dragging.
  final CropHandle? activeHandle;

  final CropAspectRatio aspectRatio;

  /// Uniform margin (0..0.5) to auto-set the crop rect.
  final double margin;

  const EditorCropState({
    this.active = false,
    this.cropRect = const Rect.fromLTRB(0, 0, 1, 1),
    this.activeHandle,
    this.aspectRatio = CropAspectRatio.freeform,
    this.margin = 0.0,
  });

  bool get hasCrop => cropRect != const Rect.fromLTRB(0, 0, 1, 1);

  EditorCropState copyWith({
    bool? active,
    Rect? cropRect,
    CropHandle? activeHandle,
    CropAspectRatio? aspectRatio,
    double? margin,
    bool clearHandle = false,
  }) =>
      EditorCropState(
        active: active ?? this.active,
        cropRect: cropRect ?? this.cropRect,
        activeHandle: clearHandle ? null : (activeHandle ?? this.activeHandle),
        aspectRatio: aspectRatio ?? this.aspectRatio,
        margin: margin ?? this.margin,
      );
}

/// Which crop handle is being dragged.
enum CropHandle { topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right }

/// Controller for the smart crop/margin tool (Phase 42).
///
/// Manages a crop rectangle over the page: freeform drag from corners/edges,
/// aspect-ratio lock, and a uniform margin setter. "Smart crop" auto-detects
/// content bounds from the text layer and sets the crop to include all content
/// plus a configurable margin. The crop rect is passed to the export service
/// to produce a cropped output.
final editorCropProvider =
    StateNotifierProvider<EditorCropController, EditorCropState>(
        (ref) => EditorCropController());

class EditorCropController extends StateNotifier<EditorCropState> {
  EditorCropController() : super(const EditorCropState());

  void activate() => state = state.copyWith(active: true);
  void deactivate() => state = const EditorCropState();

  void setAspectRatio(CropAspectRatio ar) {
    state = state.copyWith(aspectRatio: ar);
    _enforceAspect();
  }

  /// Set a uniform margin (0..0.5) and apply it to the crop rect.
  void setMargin(double margin) {
    final m = margin.clamp(0.0, 0.45);
    state = state.copyWith(
      margin: m,
      cropRect: Rect.fromLTRB(m, m, 1 - m, 1 - m),
    );
  }

  /// Smart crop: shrink the crop rect to fit content bounds + margin.
  void smartCrop(Rect contentBounds, {double padding = 0.02}) {
    final p = padding;
    final crop = Rect.fromLTRB(
      (contentBounds.left - p).clamp(0.0, 1.0),
      (contentBounds.top - p).clamp(0.0, 1.0),
      (contentBounds.right + p).clamp(0.0, 1.0),
      (contentBounds.bottom + p).clamp(0.0, 1.0),
    );
    state = state.copyWith(cropRect: crop);
  }

  /// Reset to full page.
  void resetCrop() {
    state = state.copyWith(cropRect: const Rect.fromLTRB(0, 0, 1, 1), margin: 0);
  }

  // --- drag interaction ---

  void beginDrag(CropHandle handle) {
    state = state.copyWith(activeHandle: handle);
  }

  void updateDrag(Offset point) {
    final h = state.activeHandle;
    if (h == null) return;
    final r = state.cropRect;
    Rect next;

    switch (h) {
      case CropHandle.topLeft:
        next = Rect.fromLTRB(point.dx, point.dy, r.right, r.bottom);
        break;
      case CropHandle.topRight:
        next = Rect.fromLTRB(r.left, point.dy, point.dx, r.bottom);
        break;
      case CropHandle.bottomLeft:
        next = Rect.fromLTRB(point.dx, r.top, r.right, point.dy);
        break;
      case CropHandle.bottomRight:
        next = Rect.fromLTRB(r.left, r.top, point.dx, point.dy);
        break;
      case CropHandle.top:
        next = Rect.fromLTRB(r.left, point.dy, r.right, r.bottom);
        break;
      case CropHandle.bottom:
        next = Rect.fromLTRB(r.left, r.top, r.right, point.dy);
        break;
      case CropHandle.left:
        next = Rect.fromLTRB(point.dx, r.top, r.right, r.bottom);
        break;
      case CropHandle.right:
        next = Rect.fromLTRB(r.left, r.top, point.dx, r.bottom);
        break;
    }

    // Clamp to page bounds and enforce minimum size.
    next = Rect.fromLTRB(
      next.left.clamp(0.0, next.right - 0.05),
      next.top.clamp(0.0, next.bottom - 0.05),
      next.right.clamp(next.left + 0.05, 1.0),
      next.bottom.clamp(next.top + 0.05, 1.0),
    );

    state = state.copyWith(cropRect: next);
    _enforceAspect();
  }

  void endDrag() {
    state = state.copyWith(clearHandle: true);
  }

  void _enforceAspect() {
    final ratio = state.aspectRatio.ratio;
    if (ratio == null) return;
    final r = state.cropRect;
    final currentRatio = r.width / r.height;
    if ((currentRatio - ratio).abs() < 0.01) return;

    // Adjust width to match the target ratio (keep height).
    final newWidth = (r.height * ratio).clamp(0.05, 1.0);
    final newRight = (r.left + newWidth).clamp(r.left + 0.05, 1.0);
    state = state.copyWith(cropRect: Rect.fromLTRB(r.left, r.top, newRight, r.bottom));
  }
}
