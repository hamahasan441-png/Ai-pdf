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

/// After a page is moved, inserted or deleted, furniture that is already
/// there is rewritten with the same words. Page and Bates numbers follow
/// the new page count. A plain document is left alone.
bool refreshPageDressing(Map<int, PageLayer> layers, int pageCount) {
  final watermark = _sampleText(layers, pageWatermarkKey);
  final header = _sampleText(layers, pageHeaderKey);
  final running = _sampleRunning(layers);
  if (watermark == null && header == null && running.isEmpty) return false;
  if (watermark != null) syncWatermarks(layers, pageCount, watermark);
  if (header != null) syncHeaders(layers, pageCount, header);
  for (final spec in running) {
    syncRunningLine(layers, pageCount, spec);
  }
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

/// Which edge of the page a running line sits on.
enum RunningEdge { header, footer }

/// Left, centre and right, the three FlexiPDF header and footer zones.
enum RunningSlot { left, center, right }

/// Marks one zone of a header or footer. The visible words are expanded
/// from [RunningSpec.template]; the template itself stays in metadata so a
/// later page insert can rewrite `{page}` and `{bates}`.
const String runningLineKey = 'runningLine';

/// What the user typed for one edge. Empty zones are removed.
class RunningEdgeDraft {
  final String left;
  final String center;
  final String right;
  final bool skipFirst;
  final String batesPrefix;
  final int batesStart;
  final int batesDigits;

  const RunningEdgeDraft({
    this.left = '',
    this.center = '',
    this.right = '',
    this.skipFirst = false,
    this.batesPrefix = '',
    this.batesStart = 1,
    this.batesDigits = 6,
  });

  bool get isEmpty =>
      left.trim().isEmpty && center.trim().isEmpty && right.trim().isEmpty;

  String templateFor(RunningSlot slot) => switch (slot) {
        RunningSlot.left => left,
        RunningSlot.center => center,
        RunningSlot.right => right,
      };
}

/// One zone, ready to stamp. `{page}` `{pages}` `{bates}` are expanded per page.
class RunningSpec {
  final RunningEdge edge;
  final RunningSlot slot;
  final String template;
  final bool skipFirst;
  final String batesPrefix;
  final String batesSuffix;
  final int batesStart;
  final int batesDigits;

  const RunningSpec({
    required this.edge,
    required this.slot,
    required this.template,
    this.skipFirst = false,
    this.batesPrefix = '',
    this.batesSuffix = '',
    this.batesStart = 1,
    this.batesDigits = 6,
  });
}

/// Footer-right Bates number. The first page that shows it wears [start]
/// (1 unless asked otherwise), zero-padded. FlexiPDF's default is six digits.
RunningSpec batesLine(String prefix, {int start = 1, int digits = 6, bool skipFirst = false}) {
  return RunningSpec(
    edge: RunningEdge.footer,
    slot: RunningSlot.right,
    template: '{bates}',
    skipFirst: skipFirst,
    batesPrefix: prefix,
    batesStart: start,
    batesDigits: digits,
  );
}

int clampBatesDigits(int digits) => digits.clamp(1, 8);

int clampBatesStart(int start) => start < 0 ? 0 : start;

/// The number printed for [index] when the line is actually shown.
int batesNumberFor(int index, {required bool skipFirst, required int start}) {
  final shown = skipFirst ? index - 1 : index;
  return clampBatesStart(start) + (shown < 0 ? 0 : shown);
}

String expandRunningTemplate(
  String template, {
  required int index,
  required int pageCount,
  required bool skipFirst,
  String batesPrefix = '',
  String batesSuffix = '',
  int batesStart = 1,
  int batesDigits = 6,
}) {
  final number = batesNumberFor(index, skipFirst: skipFirst, start: batesStart);
  final bates = '$batesPrefix${number.toString().padLeft(clampBatesDigits(batesDigits), '0')}$batesSuffix';
  return template
      .replaceAll('{bates}', bates)
      .replaceAll('{page}', '${index + 1}')
      .replaceAll('{pages}', '$pageCount');
}

bool isRunningLine(EditorAnnotation annotation) => annotation.metadata[runningLineKey] == true;

RunningSpec? runningSpecOf(EditorAnnotation annotation) {
  if (!isRunningLine(annotation)) return null;
  final edge = _edge(annotation.metadata['runEdge']);
  final slot = _slot(annotation.metadata['runSlot']);
  final template = annotation.metadata['runTemplate'];
  if (edge == null || slot == null || template is! String || template.trim().isEmpty) return null;
  return RunningSpec(
    edge: edge,
    slot: slot,
    template: template,
    skipFirst: annotation.metadata['runSkipFirst'] == true,
    batesPrefix: annotation.metadata['batesPrefix'] as String? ?? '',
    batesSuffix: annotation.metadata['batesSuffix'] as String? ?? '',
    batesStart: _asInt(annotation.metadata['batesStart'], 1),
    batesDigits: _asInt(annotation.metadata['batesDigits'], 6),
  );
}

/// Reads the three zones already on [edge], so the sheet opens on the
/// current words instead of a blank form.
RunningEdgeDraft readRunningEdge(Map<int, PageLayer> layers, RunningEdge edge) {
  final zones = <RunningSlot, String>{};
  var skipFirst = false;
  var prefix = '';
  var suffix = '';
  var start = 1;
  var digits = 6;
  var sawBates = false;
  final indexes = layers.keys.toList()..sort();
  for (final index in indexes) {
    for (final item in layers[index]!.items) {
      final spec = runningSpecOf(item);
      if (spec == null || spec.edge != edge) continue;
      zones.putIfAbsent(spec.slot, () => spec.template);
      if (!sawBates) {
        skipFirst = spec.skipFirst;
        prefix = spec.batesPrefix;
        suffix = spec.batesSuffix;
        start = spec.batesStart;
        digits = spec.batesDigits;
        sawBates = true;
      }
    }
  }
  return RunningEdgeDraft(
    left: zones[RunningSlot.left] ?? '',
    center: zones[RunningSlot.center] ?? '',
    right: zones[RunningSlot.right] ?? '',
    skipFirst: skipFirst,
    batesPrefix: prefix,
    batesStart: start,
    batesDigits: digits,
  );
}

/// Writes the three zones of one edge. A blank zone is removed. The old
/// single centred header is not touched here; the caller clears it when
/// the user replaces the header.
int applyRunningEdge(
  Map<int, PageLayer> layers,
  int pageCount,
  RunningEdge edge,
  RunningEdgeDraft draft,
) {
  var written = 0;
  for (final slot in RunningSlot.values) {
    written += syncRunningLine(
      layers,
      pageCount,
      RunningSpec(
        edge: edge,
        slot: slot,
        template: draft.templateFor(slot),
        skipFirst: draft.skipFirst,
        batesPrefix: draft.batesPrefix,
        batesStart: draft.batesStart,
        batesDigits: draft.batesDigits,
      ),
    );
  }
  return written;
}

/// Stamps [spec] on every page (except the first, when asked). A blank
/// template removes that zone. Returns how many visible lines were written.
int syncRunningLine(Map<int, PageLayer> layers, int pageCount, RunningSpec spec) {
  _removeRunningSlot(layers, spec.edge, spec.slot);
  final template = spec.template.trim();
  if (template.isEmpty || pageCount < 1) return 0;
  final stored = RunningSpec(
    edge: spec.edge,
    slot: spec.slot,
    template: template,
    skipFirst: spec.skipFirst,
    batesPrefix: spec.batesPrefix,
    batesSuffix: spec.batesSuffix,
    batesStart: clampBatesStart(spec.batesStart),
    batesDigits: clampBatesDigits(spec.batesDigits),
  );
  var visible = 0;
  for (var i = 0; i < pageCount; i++) {
    final layer = layers.putIfAbsent(i, PageLayer.new);
    if (stored.skipFirst && i == 0) {
      // The cover shows nothing, but the template has to live somewhere
      // or deleting every later page would forget it.
      layer.items.add(_runningBox(stored, i, pageCount, carrier: true));
      continue;
    }
    layer.items.add(_runningBox(stored, i, pageCount, carrier: false));
    visible++;
  }
  return visible;
}

TextAnnotation _runningBox(RunningSpec spec, int index, int pageCount, {required bool carrier}) {
  final frame = _slotFrame(spec.slot);
  final text = carrier
      ? ''
      : expandRunningTemplate(
          spec.template,
          index: index,
          pageCount: pageCount,
          skipFirst: spec.skipFirst,
          batesPrefix: spec.batesPrefix,
          batesSuffix: spec.batesSuffix,
          batesStart: spec.batesStart,
          batesDigits: spec.batesDigits,
        );
  final box = TextAnnotation(
    Offset(frame.$1, spec.edge == RunningEdge.header ? 0.018 : 0.915),
    text,
    const Color(0xFF1B2130),
    spec.edge == RunningEdge.header ? 0.014 : 0.013,
    false,
    textAlign: frame.$3,
    width: frame.$2,
  );
  if (carrier) box.visible = false;
  box.metadata[runningLineKey] = true;
  box.metadata['runEdge'] = spec.edge.name;
  box.metadata['runSlot'] = spec.slot.name;
  box.metadata['runTemplate'] = spec.template;
  box.metadata['runSkipFirst'] = spec.skipFirst;
  box.metadata['batesPrefix'] = spec.batesPrefix;
  box.metadata['batesSuffix'] = spec.batesSuffix;
  box.metadata['batesStart'] = spec.batesStart;
  box.metadata['batesDigits'] = spec.batesDigits;
  return box;
}

/// Left, width, alignment. The three zones share a row and do not overlap.
(double, double, TextAlign) _slotFrame(RunningSlot slot) => switch (slot) {
      RunningSlot.left => (0.04, 0.28, TextAlign.left),
      RunningSlot.center => (0.34, 0.32, TextAlign.center),
      RunningSlot.right => (0.68, 0.28, TextAlign.right),
    };

void _removeRunningSlot(Map<int, PageLayer> layers, RunningEdge edge, RunningSlot slot) {
  for (final layer in layers.values) {
    layer.items.removeWhere((item) {
      final spec = runningSpecOf(item);
      return spec != null && spec.edge == edge && spec.slot == slot;
    });
  }
}

List<RunningSpec> _sampleRunning(Map<int, PageLayer> layers) {
  final seen = <String, RunningSpec>{};
  final indexes = layers.keys.toList()..sort();
  for (final index in indexes) {
    for (final item in layers[index]!.items) {
      final spec = runningSpecOf(item);
      if (spec == null) continue;
      seen.putIfAbsent('${spec.edge.name}:${spec.slot.name}', () => spec);
    }
  }
  return seen.values.toList();
}

RunningEdge? _edge(Object? value) => switch (value) {
      'header' => RunningEdge.header,
      'footer' => RunningEdge.footer,
      _ => null,
    };

RunningSlot? _slot(Object? value) => switch (value) {
      'left' => RunningSlot.left,
      'center' => RunningSlot.center,
      'right' => RunningSlot.right,
      _ => null,
    };

int _asInt(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}
