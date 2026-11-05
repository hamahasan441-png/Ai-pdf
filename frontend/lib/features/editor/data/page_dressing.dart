import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// A faint line of real text across the middle of every page.
///
/// PDF24 burns this into a page image. This stays searchable text, the same
/// way page numbers do, and a later pass rewrites it instead of stacking.
const String pageWatermarkKey = 'pageWatermark';

/// A running header at the top of every page. FlexiPDF treats this as
/// document furniture: insert or delete a page and the words stay.
const String pageHeaderKey = 'pageHeader';

bool isPageWatermark(EditorAnnotation annotation) =>
    annotation.metadata[pageWatermarkKey] == true;

bool isPageHeader(EditorAnnotation annotation) =>
    annotation.metadata[pageHeaderKey] == true;

/// Upright, not rotated. A rotated box cannot be exported as vector text,
/// so the page would be flattened — the thing this editor refuses to do.
TextAnnotation pageWatermark(String text) {
  const width = 0.84;
  const size = 0.042;
  final box = TextAnnotation(
    Offset((1 - width) / 2, (1 - size * 1.3) / 2),
    text.trim(),
    const Color(0xFF5C6570),
    size,
    true,
    textAlign: TextAlign.center,
    width: width,
  );
  box.opacity = 0.22;
  box.metadata[pageWatermarkKey] = true;
  return box;
}

TextAnnotation pageHeader(String text) {
  const width = 0.86;
  final box = TextAnnotation(
    const Offset((1 - width) / 2, 0.02),
    text.trim(),
    const Color(0xFF1B2130),
    0.016,
    false,
    textAlign: TextAlign.center,
    width: width,
  );
  box.metadata[pageHeaderKey] = true;
  return box;
}

/// Writes one watermark on every page. Blank [text] removes them.
int syncWatermarks(Map<int, PageLayer> layers, int pageCount, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return clearMarkedText(layers, pageWatermarkKey);
  return _syncMarked(layers, pageCount, pageWatermarkKey, () => pageWatermark(trimmed));
}

/// Writes one header on every page. Blank [text] removes them.
int syncHeaders(Map<int, PageLayer> layers, int pageCount, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return clearMarkedText(layers, pageHeaderKey);
  return _syncMarked(layers, pageCount, pageHeaderKey, () => pageHeader(trimmed));
}

int clearMarkedText(Map<int, PageLayer> layers, String key) {
  var removed = 0;
  for (final layer in layers.values) {
    final before = layer.items.length;
    layer.items.removeWhere((a) => a.metadata[key] == true);
    removed += before - layer.items.length;
  }
  return removed;
}

/// After a page is moved, inserted or deleted, a watermark or header that
/// is already there is rewritten with the same words. A plain document
/// is left alone.
bool refreshPageDressing(Map<int, PageLayer> layers, int pageCount) {
  final watermark = _sampleText(layers, pageWatermarkKey);
  final header = _sampleText(layers, pageHeaderKey);
  if (watermark == null && header == null) return false;
  if (watermark != null) syncWatermarks(layers, pageCount, watermark);
  if (header != null) syncHeaders(layers, pageCount, header);
  return true;
}

String? _sampleText(Map<int, PageLayer> layers, String key) {
  final indexes = layers.keys.toList()..sort();
  for (final index in indexes) {
    for (final item in layers[index]!.items) {
      if (item.metadata[key] == true && item is TextAnnotation && item.text.trim().isNotEmpty) {
        return item.text;
      }
    }
  }
  return null;
}

int _syncMarked(
  Map<int, PageLayer> layers,
  int pageCount,
  String key,
  TextAnnotation Function() build,
) {
  for (final layer in layers.values) {
    layer.items.removeWhere((a) => a.metadata[key] == true);
  }
  if (pageCount < 1) return 0;
  for (var i = 0; i < pageCount; i++) {
    layers.putIfAbsent(i, PageLayer.new).items.add(build());
  }
  return pageCount;
}
