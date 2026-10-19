import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';

bool _same(Color a, Color b) => a.toARGB32() == b.toARGB32();

class EditorToolbar extends StatelessWidget {
  static const List<Color> presets = [Color(0xFFFFEB3B), Colors.red, Colors.blue, Colors.black, Colors.green];

  /// The swatches in the style row: the presets, then the current or most
  /// recent colour that is not a preset, so a picked colour stays one tap
  /// away. One extra only: on a 360 dp phone the size slider needs the rest.
  static List<Color> quickColors(Color current, List<Color> recent) {
    final extra = <Color>[];
    for (final c in [current, ...recent]) {
      if (extra.isNotEmpty) break;
      if (presets.any((p) => _same(p, c)) || extra.any((e) => _same(e, c))) continue;
      extra.add(c);
    }
    return [...presets, ...extra];
  }

  final EditTool tool;
  final bool detecting;
  final bool showFields;
  final bool showEditLines;
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
  final VoidCallback onOpen;
  final VoidCallback? onSearch;
  final VoidCallback? onRedact;
  final VoidCallback? onOutline;
  final VoidCallback? onChat;
  final VoidCallback? onLayers;
  final VoidCallback? onPageOps;
  final VoidCallback? onReadingMode;
  final VoidCallback? onReadingView;
  final ValueChanged<Color> onColorChanged;

  /// Opens the full colour picker. The button is hidden when null.
  final VoidCallback? onPickColor;

  /// Recently picked colours; the newest that is not a preset is shown.
  final List<Color> recentColors;
  final ValueChanged<double> onStrokeChanged;
  final ValueChanged<double> onTextSizeChanged;
  final VoidCallback onToggleBold;

  const EditorToolbar({
    super.key,
    required this.tool,
    required this.detecting,
    required this.showFields,
    required this.showEditLines,
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
    required this.onOpen,
    this.onSearch,
    this.onRedact,
    this.onOutline,
    this.onChat,
    this.onLayers,
    this.onPageOps,
    this.onReadingMode,
    this.onReadingView,
    required this.onColorChanged,
    this.onPickColor,
    this.recentColors = const [],
    required this.onStrokeChanged,
    required this.onTextSizeChanged,
    required this.onToggleBold,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final showStyle = tool == EditTool.draw ||
        tool == EditTool.highlight ||
        tool == EditTool.underline ||
        tool == EditTool.strikeout ||
        tool == EditTool.squiggly ||
        tool == EditTool.text ||
        isShape;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  _toolBtn(Icons.pan_tool_alt, l10n.toolMove, EditTool.pan, cs),
                  _toolBtn(Icons.near_me_outlined, l10n.toolSelect, EditTool.select, cs),
                  _toolBtn(Icons.highlight, l10n.toolHighlight, EditTool.highlight, cs),
                  _toolBtn(Icons.format_underlined, l10n.toolUnderline, EditTool.underline, cs),
                  _toolBtn(Icons.title, l10n.toolText, EditTool.text, cs),
                  _toolBtn(Icons.edit, l10n.toolDraw, EditTool.draw, cs),
                  _toolBtn(Icons.sticky_note_2_outlined, l10n.toolNote, EditTool.note, cs),
                  _actionBtn(Icons.gesture, l10n.toolSign, onAddSignature, cs),
                  if (onSearch != null) _actionBtn(Icons.search, l10n.toolFind, onSearch!, cs),
                  if (!_isPrimary(tool)) _overflowTool(l10n, cs),
                  _actionBtn(Icons.apps, l10n.toolMore, () => _openMore(context), cs),
                ],
              ),
            ),
            if (showStyle)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 10, right: 10),
                child: Row(
                  children: [
                    ...quickColors(color, recentColors).map(
                      (c) => Semantics(
                        button: true,
                        selected: _same(color, c),
                        label: 'Colour',
                        child: GestureDetector(
                          onTap: () => onColorChanged(c),
                          child: Container(
                            width: 26,
                            height: 26,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _same(color, c) ? cs.primary : Colors.grey.shade400,
                                width: _same(color, c) ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (onPickColor != null)
                      IconButton(
                        tooltip: l10n.colorMore,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.palette_outlined),
                        onPressed: onPickColor,
                      ),
                    if (tool == EditTool.draw || isShape)
                      Expanded(
                        child: Slider(
                          value: stroke,
                          min: 1,
                          max: 12,
                          onChanged: onStrokeChanged,
                        ),
                      ),
                    if (tool == EditTool.text) ...[
                      Expanded(
                        child: Slider(
                          value: textSize,
                          min: 0.008,
                          max: 0.08,
                          onChanged: onTextSizeChanged,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.bold,
                        isSelected: bold,
                        icon: const Icon(Icons.format_bold),
                        onPressed: onToggleBold,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isPrimary(EditTool value) {
    return value == EditTool.pan ||
        value == EditTool.select ||
        value == EditTool.highlight ||
        value == EditTool.underline ||
        value == EditTool.text ||
        value == EditTool.draw ||
        value == EditTool.note;
  }

  Widget _overflowTool(AppLocalizations l10n, ColorScheme cs) {
    switch (tool) {
      case EditTool.strikeout:
        return _toolBtn(Icons.format_strikethrough, l10n.toolStrikeout, tool, cs);
      case EditTool.squiggly:
        return _toolBtn(Icons.waves, l10n.toolSquiggly, tool, cs);
      case EditTool.line:
        return _toolBtn(Icons.horizontal_rule, l10n.toolLine, tool, cs);
      case EditTool.arrow:
        return _toolBtn(Icons.north_east, l10n.toolArrow, tool, cs);
      case EditTool.rect:
        return _toolBtn(Icons.crop_square, l10n.toolBox, tool, cs);
      case EditTool.oval:
        return _toolBtn(Icons.circle_outlined, l10n.toolOval, tool, cs);
      case EditTool.whiteout:
        return _toolBtn(Icons.format_color_fill, l10n.toolWhiteout, tool, cs);
      case EditTool.eraser:
        return _toolBtn(Icons.cleaning_services, l10n.toolEraser, tool, cs);
      case EditTool.check:
        return _toolBtn(Icons.check, l10n.markCheck, tool, cs);
      case EditTool.cross:
        return _toolBtn(Icons.close, l10n.markCross, tool, cs);
      case EditTool.checkbox:
        return _toolBtn(Icons.check_box_outlined, l10n.markCheckbox, tool, cs);
      case EditTool.dot:
        return _toolBtn(Icons.fiber_manual_record, l10n.markDot, tool, cs);
      case EditTool.dash:
        return _toolBtn(Icons.remove, l10n.markDash, tool, cs);
      default:
        return const SizedBox.shrink();
    }
  }

  void _openMore(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        void act(VoidCallback action) {
          Navigator.pop(ctx);
          action();
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              _moreLabel(l10n.toolHighlight, cs),
              Wrap(
                children: [
                  _sheetTool(ctx, Icons.format_strikethrough, l10n.toolStrikeout, EditTool.strikeout),
                  _sheetTool(ctx, Icons.waves, l10n.toolSquiggly, EditTool.squiggly),
                ],
              ),
              _moreLabel(l10n.moreShapes, cs),
              Wrap(
                children: [
                  _sheetTool(ctx, Icons.horizontal_rule, l10n.toolLine, EditTool.line),
                  _sheetTool(ctx, Icons.north_east, l10n.toolArrow, EditTool.arrow),
                  _sheetTool(ctx, Icons.crop_square, l10n.toolBox, EditTool.rect),
                  _sheetTool(ctx, Icons.circle_outlined, l10n.toolOval, EditTool.oval),
                  _sheetTool(ctx, Icons.format_color_fill, l10n.toolWhiteout, EditTool.whiteout),
                  _sheetTool(ctx, Icons.cleaning_services, l10n.toolEraser, EditTool.eraser),
                  _sheetTool(ctx, Icons.check, l10n.markCheck, EditTool.check),
                  _sheetTool(ctx, Icons.close, l10n.markCross, EditTool.cross),
                  _sheetTool(ctx, Icons.check_box_outlined, l10n.markCheckbox, EditTool.checkbox),
                  _sheetTool(ctx, Icons.fiber_manual_record, l10n.markDot, EditTool.dot),
                  _sheetTool(ctx, Icons.remove, l10n.markDash, EditTool.dash),
                ],
              ),
              _moreLabel(l10n.moreInsert, cs),
              Wrap(
                children: [
                  _actionBtn(Icons.approval, l10n.toolStamp, () => act(onAddStamp), cs),
                  _actionBtn(Icons.image_outlined, l10n.toolImage, () => act(onAddImage), cs),
                  _actionBtn(Icons.event_available, l10n.signatureDate, () => act(onPlaceSignatureDate), cs),
                  _actionBtn(Icons.badge_outlined, l10n.myProfile, () => act(onInsertProfileField), cs),
                  if (onAddFormField != null)
                    _actionBtn(Icons.dynamic_form_outlined, l10n.addFormField, () => act(onAddFormField!), cs),
                ],
              ),
              _moreLabel(l10n.moreDocument, cs),
              Wrap(
                children: [
                  _actionBtn(Icons.auto_fix_high, l10n.autoFill, () => act(detecting ? () {} : onAutoFill), cs),
                  _actionBtn(Icons.psychology, l10n.aiFill, () => act(detecting ? () {} : onAiFill), cs),
                  _actionBtn(
                    showEditLines ? Icons.text_fields : Icons.text_format,
                    l10n.editTextTool,
                    () => act(detecting ? () {} : onEditTextTool),
                    cs,
                  ),
                  if (hasPageFields)
                    _actionBtn(
                      showFields ? Icons.visibility_off : Icons.visibility,
                      showFields ? l10n.toolHide : l10n.toolFields,
                      () => act(onToggleFields),
                      cs,
                    ),
                  _actionBtn(Icons.rotate_right, l10n.rotate, () => act(onRotatePage), cs),
                  if (onRedact != null)
                    _actionBtn(Icons.remove_red_eye_outlined, l10n.toolRedact, () => act(onRedact!), cs),
                  if (onOutline != null)
                    _actionBtn(Icons.menu_book, l10n.toolOutline, () => act(onOutline!), cs),
                  if (onLayers != null)
                    _actionBtn(Icons.layers, l10n.toolLayers, () => act(onLayers!), cs),
                  if (onChat != null)
                    _actionBtn(Icons.auto_awesome, l10n.toolChat, () => act(onChat!), cs),
                  if (onPageOps != null)
                    _actionBtn(Icons.pages, l10n.toolPages, () => act(onPageOps!), cs),
                  if (onReadingView != null)
                    _actionBtn(Icons.view_agenda_outlined, l10n.toolReadView, () => act(onReadingView!), cs),
                  if (onReadingMode != null)
                    _actionBtn(Icons.contrast, l10n.toolReadingMode, () => act(onReadingMode!), cs),
                  _actionBtn(Icons.folder_open, l10n.toolOpen, () => act(onOpen), cs),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetTool(BuildContext ctx, IconData icon, String label, EditTool value) {
    return _actionBtn(icon, label, () {
      Navigator.pop(ctx);
      onToolChanged(value);
    }, Theme.of(ctx).colorScheme);
  }

  Widget _moreLabel(String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
    );
  }

  Widget _toolBtn(IconData icon, String label, EditTool value, ColorScheme cs) {
    final active = tool == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => onToolChanged(value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: active ? cs.primary : cs.onSurface),
              Text(label, style: TextStyle(fontSize: 10, color: active ? cs.primary : cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: cs.onSurface),
              Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
