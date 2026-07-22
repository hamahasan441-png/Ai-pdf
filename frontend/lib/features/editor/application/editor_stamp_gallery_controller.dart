import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A stamp available in the gallery (Phase 48).
class StampItem {
  final String id;
  final String label;
  final StampCategory category;
  final StampStyle style;
  final int color;
  final Uint8List? imageBytes;
  final bool builtIn;
  final DateTime createdAt;

  const StampItem({
    required this.id,
    required this.label,
    required this.category,
    this.style = StampStyle.bordered,
    this.color = 0xFFF44336,
    this.imageBytes,
    this.builtIn = false,
    required this.createdAt,
  });

  bool get isImage => imageBytes != null;
}

enum StampCategory { approval, status, confidential, custom }
enum StampStyle { bordered, filled, badge, image }

/// UI state for the stamp gallery (Phase 48).
class EditorStampGalleryState {
  final bool visible;
  final List<StampItem> stamps;
  final StampCategory? filterCategory;

  const EditorStampGalleryState({
    this.visible = false,
    this.stamps = const [],
    this.filterCategory,
  });

  bool get hasStamps => stamps.isNotEmpty;

  List<StampItem> get filtered => filterCategory == null
      ? stamps
      : stamps.where((s) => s.category == filterCategory).toList();

  List<StampCategory> get categories => [
        ...{for (final s in stamps) s.category},
      ];

  EditorStampGalleryState copyWith({
    bool? visible,
    List<StampItem>? stamps,
    StampCategory? filterCategory,
    bool clearFilter = false,
  }) =>
      EditorStampGalleryState(
        visible: visible ?? this.visible,
        stamps: stamps ?? this.stamps,
        filterCategory:
            clearFilter ? null : (filterCategory ?? this.filterCategory),
      );
}

/// Controller for the stamp gallery (Phase 48).
///
/// A rich library of text stamps (APPROVED, DRAFT, CONFIDENTIAL, VOID, etc.)
/// and custom image stamps. Built-in stamps come pre-configured; users can add
/// their own custom image stamps from file/camera. Gallery panel with category
/// filter; tap to place on the page.
final editorStampGalleryProvider =
    StateNotifierProvider<EditorStampGalleryController, EditorStampGalleryState>(
        (ref) => EditorStampGalleryController());

class EditorStampGalleryController
    extends StateNotifier<EditorStampGalleryState> {
  EditorStampGalleryController() : super(const EditorStampGalleryState()) {
    _loadBuiltIns();
  }

  int _nextId = 1;

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  void setFilter(StampCategory? category) =>
      state = state.copyWith(filterCategory: category, clearFilter: category == null);

  /// Add a custom text stamp.
  StampItem addTextStamp({
    required String label,
    StampCategory category = StampCategory.custom,
    StampStyle style = StampStyle.bordered,
    int color = 0xFFF44336,
  }) {
    final stamp = StampItem(
      id: 'stamp_${_nextId++}',
      label: label,
      category: category,
      style: style,
      color: color,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(stamps: [...state.stamps, stamp]);
    return stamp;
  }

  /// Add a custom image stamp.
  StampItem addImageStamp({
    required String label,
    required Uint8List imageBytes,
  }) {
    final stamp = StampItem(
      id: 'stamp_${_nextId++}',
      label: label,
      category: StampCategory.custom,
      style: StampStyle.image,
      imageBytes: imageBytes,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(stamps: [...state.stamps, stamp]);
    return stamp;
  }

  /// Delete a user stamp (built-ins can't be deleted).
  void delete(String id) {
    state = state.copyWith(
      stamps: [for (final s in state.stamps) if (s.id != id || s.builtIn) s],
    );
  }

  void _loadBuiltIns() {
    final now = DateTime(2024);
    final builtIns = [
      StampItem(id: 'b_approved', label: 'APPROVED', category: StampCategory.approval, color: 0xFF4CAF50, style: StampStyle.bordered, builtIn: true, createdAt: now),
      StampItem(id: 'b_rejected', label: 'REJECTED', category: StampCategory.approval, color: 0xFFF44336, style: StampStyle.bordered, builtIn: true, createdAt: now),
      StampItem(id: 'b_draft', label: 'DRAFT', category: StampCategory.status, color: 0xFFFF9800, style: StampStyle.bordered, builtIn: true, createdAt: now),
      StampItem(id: 'b_final', label: 'FINAL', category: StampCategory.status, color: 0xFF2196F3, style: StampStyle.bordered, builtIn: true, createdAt: now),
      StampItem(id: 'b_void', label: 'VOID', category: StampCategory.status, color: 0xFF9E9E9E, style: StampStyle.filled, builtIn: true, createdAt: now),
      StampItem(id: 'b_confidential', label: 'CONFIDENTIAL', category: StampCategory.confidential, color: 0xFFF44336, style: StampStyle.badge, builtIn: true, createdAt: now),
      StampItem(id: 'b_copy', label: 'COPY', category: StampCategory.status, color: 0xFF9C27B0, style: StampStyle.bordered, builtIn: true, createdAt: now),
      StampItem(id: 'b_original', label: 'ORIGINAL', category: StampCategory.status, color: 0xFF009688, style: StampStyle.bordered, builtIn: true, createdAt: now),
      StampItem(id: 'b_urgent', label: 'URGENT', category: StampCategory.status, color: 0xFFE91E63, style: StampStyle.filled, builtIn: true, createdAt: now),
      StampItem(id: 'b_foraction', label: 'FOR ACTION', category: StampCategory.approval, color: 0xFFFF5722, style: StampStyle.bordered, builtIn: true, createdAt: now),
    ];
    state = state.copyWith(stamps: builtIns);
  }
}
