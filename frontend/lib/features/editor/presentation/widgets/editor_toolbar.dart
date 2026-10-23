import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/core/theme/motion.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_mode.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_mode_bar.dart';

bool _same(Color a, Color b) => a.toARGB32() == b.toARGB32();

/// The editor's bottom bars: the tools of the current workspace in one
/// slim row (icons, names on long press), then the workspace bar. Colour
/// and size live behind one chip instead of a permanent swatch row, so the
/// page keeps the screen.
class EditorToolbar extends StatelessWidget {
  static const List<Color> presets = [Color(0xFFFFEB3B), Colors.red, Colors.blue, Colors.black, Colors.green];

  /// The swatches offered: the presets, then the current or most recent
  /// colour that is not a preset, so a picked colour stays one tap away.
  static List<Color> quickColors(Color current, List<Color> recent) {
    final extra = <Color>[];
    for (final c in [current, ...recent]) {
      if (extra.isNotEmpty) break;
      if (presets.any((p) => _same(p, c)) || extra.any((e) => _same(e, c))) continue;
      extra.add(c);
    }
    return [...presets, ...extra];
  }

  static const double rowHeight = 56;

  final EditorMode mode;
  final ValueChanged<EditorMode> onModeChanged;
  final EditTool tool;
  final bool detecting;

  /// Editing the document's own text is switched on.
  final bool editingText;
  final bool showFields;
  final bool hasPageFields;
  final bool isShape;
  final Color color;
  final double stroke;
  final double textSize;
  final bool bold;
  final ValueChanged<EditTool> onToolChanged;
  final VoidCallback onAutoFill;
  final VoidCallback onAiFill;
  final VoidCallback onEditTextTool;

  /// Adds a fillable form field; hidden when null.
  final VoidCallback? onAddFormField;
  final VoidCallback onToggleFields;
  final VoidCallback onAddSignature;
  final VoidCallback onPlaceSignatureDate;
  final VoidCallback onInsertProfileField;
  final VoidCallback onRotatePage;
  final VoidCallback onAddStamp;
  final VoidCallback onAddImage;
  final VoidCallback? onSearch;
  final VoidCallback? onRedact;
  final VoidCallback? onOutline;
  final VoidCallback? onPageOps;
  final ValueChanged<Color> onColorChanged;

  /// Opens the full colour picker. The button is hidden when null.
  final VoidCallback? onPickColor;

  /// Recently picked colours; the newest that is not a preset is offered.
  final List<Color> recentColors;
  final ValueChanged<double> onStrokeChanged;
  final ValueChanged<double> onTextSizeChanged;
  final VoidCallback onToggleBold;

  /// The page thumbnails, shown in the Pages workspace.
  final Widget? pageStrip;

  const EditorToolbar({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.tool,
    required this.detecting,
    this.editingText = false,
    required this.showFields,
    required this.hasPageFields,
    required this.isShape,
    required this.color,
    required this.stroke,
    required this.textSize,
    required this.bold,
    required this.onToolChanged,
    required this.onAutoFill,
    required this.onAiFill,
    required this.onEditTextTool,
    this.onAddFormField,
    required this.onToggleFields,
    required this.onAddSignature,
    required this.onPlaceSignatureDate,
    required this.onInsertProfileField,
    required this.onRotatePage,
    required this.onAddStamp,
    required this.onAddImage,
    this.onSearch,
    this.onRedact,
    this.onOutline,
    this.onPageOps,
    required this.onColorChanged,
    this.onPickColor,
    this.recentColors = const [],
    required this.onStrokeChanged,
    required this.onTextSizeChanged,
    required this.onToggleBold,
    this.pageStrip,
  });

  bool get _usesStyle =>
      tool == EditTool.draw ||
      tool == EditTool.highlight ||
      tool == EditTool.underline ||
      tool == EditTool.strikeout ||
      tool == EditTool.squiggly ||
      tool == EditTool.text ||
      isShape;

  @override
  Widget build(BuildContext context) {
    final palette = EditorPalette.of(context);
    final row = _toolRow(context, palette);
    final strip = mode == EditorMode.pages ? pageStrip : null;
    return Material(
      color: palette.barSurface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.hairline))),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: Motion.of(context, Motion.quick),
                curve: Motion.enter,
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (strip != null) strip,
                    if (row != null) ...[
                      SizedBox(height: rowHeight, child: KeyedSubtree(key: ValueKey(mode), child: row)),
                      Divider(height: 1, thickness: 1, color: palette.hairline),
                    ],
                  ],
                ),
              ),
              EditorModeBar(mode: mode, onChanged: onModeChanged),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _toolRow(BuildContext context, EditorPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    final List<Widget> items;
    switch (mode) {
      case EditorMode.view:
        return null;
      case EditorMode.annotate:
        items = [
          if (_usesStyle) ...[_StyleChip(color: color, onTap: () => _openStyleSheet(context)), _divider(palette)],
          _tool(Icons.near_me_outlined, l10n.toolSelect, EditTool.select, palette),
          _tool(Icons.border_color_outlined, l10n.toolHighlight, EditTool.highlight, palette),
          _tool(Icons.format_underlined, l10n.toolUnderline, EditTool.underline, palette),
          _tool(Icons.format_strikethrough, l10n.toolStrikeout, EditTool.strikeout, palette),
          _tool(Icons.gesture, l10n.toolDraw, EditTool.draw, palette),
          _menu(
            context,
            palette,
            icon: _shapeIcon(tool) ?? Icons.category_outlined,
            tooltip: l10n.moreShapes,
            active: isShape,
            entries: [
              _Entry(Icons.horizontal_rule, l10n.toolLine, () => onToolChanged(EditTool.line), tool == EditTool.line),
              _Entry(Icons.north_east, l10n.toolArrow, () => onToolChanged(EditTool.arrow), tool == EditTool.arrow),
              _Entry(Icons.crop_square, l10n.toolBox, () => onToolChanged(EditTool.rect), tool == EditTool.rect),
              _Entry(Icons.circle_outlined, l10n.toolOval, () => onToolChanged(EditTool.oval), tool == EditTool.oval),
              _Entry(Icons.format_color_fill, l10n.toolWhiteout, () => onToolChanged(EditTool.whiteout),
                  tool == EditTool.whiteout),
            ],
          ),
          _tool(Icons.sticky_note_2_outlined, l10n.toolNote, EditTool.note, palette),
          _tool(Icons.cleaning_services_outlined, l10n.toolEraser, EditTool.eraser, palette),
          _menu(
            context,
            palette,
            icon: Icons.more_horiz,
            tooltip: l10n.toolMore,
            active: tool == EditTool.squiggly || tool == EditTool.dot || tool == EditTool.dash,
            entries: [
              _Entry(Icons.waves, l10n.toolSquiggly, () => onToolChanged(EditTool.squiggly), tool == EditTool.squiggly),
              _Entry(Icons.approval_outlined, l10n.toolStamp, onAddStamp),
              _Entry(Icons.image_outlined, l10n.toolImage, onAddImage),
              _Entry(Icons.fiber_manual_record_outlined, l10n.markDot, () => onToolChanged(EditTool.dot),
                  tool == EditTool.dot),
              _Entry(Icons.remove, l10n.markDash, () => onToolChanged(EditTool.dash), tool == EditTool.dash),
              if (onRedact != null) _Entry(Icons.remove_red_eye_outlined, l10n.toolRedact, onRedact!),
            ],
          ),
        ];
      case EditorMode.text:
        items = [
          _action(Icons.edit_note, l10n.editTextTool, detecting ? null : onEditTextTool, palette, active: editingText),
          _tool(Icons.title, l10n.toolText, EditTool.text, palette),
          if (tool == EditTool.text) ...[
            _divider(palette),
            _StyleChip(color: color, onTap: () => _openStyleSheet(context)),
          ],
          if (onSearch != null) ...[_divider(palette), _action(Icons.find_replace, l10n.toolFind, onSearch, palette)],
        ];
      case EditorMode.sign:
        items = [
          _menu(
            context,
            palette,
            icon: Icons.auto_awesome_outlined,
            tooltip: l10n.autoFill,
            label: l10n.autoFill,
            enabled: !detecting,
            entries: [
              _Entry(Icons.auto_fix_high, l10n.autoFill, onAutoFill),
              _Entry(Icons.psychology_outlined, l10n.aiFill, onAiFill),
            ],
          ),
          _divider(palette),
          _action(Icons.draw_outlined, l10n.toolSign, onAddSignature, palette),
          _action(Icons.event_available_outlined, l10n.signatureDate, onPlaceSignatureDate, palette),
          _tool(Icons.check, l10n.markCheck, EditTool.check, palette),
          _tool(Icons.close, l10n.markCross, EditTool.cross, palette),
          _tool(Icons.check_box_outlined, l10n.markCheckbox, EditTool.checkbox, palette),
          _action(Icons.badge_outlined, l10n.myProfile, onInsertProfileField, palette),
          if (onAddFormField != null) _action(Icons.dynamic_form_outlined, l10n.addFormField, onAddFormField, palette),
          if (hasPageFields)
            _action(showFields ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                showFields ? l10n.toolHide : l10n.toolFields, onToggleFields, palette,
                active: showFields),
        ];
      case EditorMode.pages:
        items = [
          _action(Icons.rotate_right, l10n.rotate, onRotatePage, palette),
          if (onPageOps != null) _action(Icons.auto_stories_outlined, l10n.toolPages, onPageOps, palette),
          if (onOutline != null) _action(Icons.menu_book_outlined, l10n.toolOutline, onOutline, palette),
        ];
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: items),
    );
  }

  static IconData? _shapeIcon(EditTool t) => switch (t) {
        EditTool.line => Icons.horizontal_rule,
        EditTool.arrow => Icons.north_east,
        EditTool.rect => Icons.crop_square,
        EditTool.oval => Icons.circle_outlined,
        EditTool.whiteout => Icons.format_color_fill,
        _ => null,
      };

  Widget _tool(IconData icon, String label, EditTool value, EditorPalette palette) =>
      _IconTool(icon: icon, label: label, active: tool == value, palette: palette, onTap: () => onToolChanged(value));

  Widget _action(IconData icon, String label, VoidCallback? onTap, EditorPalette palette, {bool active = false}) =>
      _IconTool(icon: icon, label: label, active: active, palette: palette, onTap: onTap);

  Widget _divider(EditorPalette palette) => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: palette.hairline,
      );

  Widget _menu(
    BuildContext context,
    EditorPalette palette, {
    required IconData icon,
    required String tooltip,
    required List<_Entry> entries,
    String? label,
    bool active = false,
    bool enabled = true,
  }) {
    final fg = !enabled ? palette.barMuted.withValues(alpha: 0.4) : (active || label != null ? palette.accent : palette.barForeground);
    return PopupMenuButton<int>(
      tooltip: tooltip,
      enabled: enabled,
      position: PopupMenuPosition.over,
      onSelected: (i) => entries[i].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(children: [
              Icon(entries[i].icon, size: 20, color: entries[i].selected ? palette.accent : null),
              const SizedBox(width: 12),
              Expanded(child: Text(entries[i].label)),
              if (entries[i].selected) Icon(Icons.check, size: 18, color: palette.accent),
            ]),
          ),
      ],
      child: Container(
        height: 44,
        constraints: const BoxConstraints(minWidth: 44),
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 12),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: active ? palette.activePill : Colors.transparent,
          border: label == null ? null : Border.all(color: palette.hairline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: label == null ? 22 : 18, color: fg),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ],
          ],
        ),
      ),
    );
  }

  /// Colour, thickness and text size for the current tool, in one sheet.
  void _openStyleSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    var current = color;
    var width = stroke;
    var size = textSize;
    var isBold = bold;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.toolStyle, style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final c in quickColors(current, recentColors))
                        Semantics(
                          button: true,
                          selected: _same(current, c),
                          label: l10n.colorTitle,
                          child: InkResponse(
                            radius: 24,
                            onTap: () {
                              setSheet(() => current = c);
                              onColorChanged(c);
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
                                boxShadow: _same(current, c)
                                    ? [BoxShadow(color: cs.onSurface, spreadRadius: 2.5), BoxShadow(color: cs.surface, spreadRadius: 1)]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      if (onPickColor != null)
                        IconButton(
                          tooltip: l10n.colorMore,
                          icon: const Icon(Icons.palette_outlined),
                          onPressed: () {
                            Navigator.pop(ctx);
                            onPickColor!();
                          },
                        ),
                    ],
                  ),
                  if (tool == EditTool.draw || isShape) ...[
                    const SizedBox(height: 20),
                    Text(l10n.toolThickness, style: TextStyle(color: cs.onSurfaceVariant)),
                    Slider(
                      value: width.clamp(1, 12).toDouble(),
                      min: 1,
                      max: 12,
                      onChanged: (v) {
                        setSheet(() => width = v);
                        onStrokeChanged(v);
                      },
                    ),
                  ],
                  if (tool == EditTool.text) ...[
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: Text(l10n.toolTextSize, style: TextStyle(color: cs.onSurfaceVariant))),
                      IconButton(
                        tooltip: l10n.bold,
                        isSelected: isBold,
                        icon: const Icon(Icons.format_bold),
                        onPressed: () {
                          setSheet(() => isBold = !isBold);
                          onToggleBold();
                        },
                      ),
                    ]),
                    Slider(
                      value: size.clamp(0.008, 0.08).toDouble(),
                      min: 0.008,
                      max: 0.08,
                      onChanged: (v) {
                        setSheet(() => size = v);
                        onTextSizeChanged(v);
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Entry {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _Entry(this.icon, this.label, this.onTap, [this.selected = false]);
}

/// One tool: an icon with its name as tooltip and for screen readers. The
/// active one sits on a quiet pill in the accent colour.
class _IconTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final EditorPalette palette;
  final VoidCallback? onTap;

  const _IconTool({
    required this.icon,
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = !enabled ? palette.barMuted.withValues(alpha: 0.4) : (active ? palette.accent : palette.barForeground);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: active,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.quick),
                curve: Motion.enter,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: active ? palette.activePill : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The current colour as a dot: opens colour, thickness and size.
class _StyleChip extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _StyleChip({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = EditorPalette.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: l10n.toolStyle,
      child: Semantics(
        button: true,
        label: l10n.toolStyle,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: palette.hairline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 18, color: palette.barMuted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
