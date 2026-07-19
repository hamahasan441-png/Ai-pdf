import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';

class EditorToolbar extends StatelessWidget {
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
  final VoidCallback onToggleFields;
  final VoidCallback onAddSignature;
  final VoidCallback onPlaceSignatureDate;
  final VoidCallback onInsertProfileField;
  final VoidCallback onRotatePage;
  final VoidCallback onOpen;
  final ValueChanged<Color> onColorChanged;
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
    required this.onToggleFields,
    required this.onAddSignature,
    required this.onPlaceSignatureDate,
    required this.onInsertProfileField,
    required this.onRotatePage,
    required this.onOpen,
    required this.onColorChanged,
    required this.onStrokeChanged,
    required this.onTextSizeChanged,
    required this.onToggleBold,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final showStyle = tool == EditTool.draw || tool == EditTool.highlight || tool == EditTool.text || isShape;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, -2))],
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
                  _actionBtn(Icons.auto_fix_high, l10n.autoFill, detecting ? () {} : onAutoFill, cs),
                  _actionBtn(Icons.psychology, l10n.aiFill, detecting ? () {} : onAiFill, cs),
                  _actionBtn(
                    showEditLines ? Icons.text_fields : Icons.text_format,
                    l10n.editTextTool,
                    detecting ? () {} : onEditTextTool,
                    cs,
                  ),
                  if (hasPageFields)
                    _actionBtn(
                      showFields ? Icons.visibility_off : Icons.visibility,
                      showFields ? l10n.toolHide : l10n.toolFields,
                      onToggleFields,
                      cs,
                    ),
                  _toolBtn(Icons.pan_tool_alt, l10n.toolMove, EditTool.pan, cs),
                  _actionBtn(Icons.gesture, l10n.toolSign, onAddSignature, cs),
                  _actionBtn(Icons.event_available, l10n.signatureDate, onPlaceSignatureDate, cs),
                  _actionBtn(Icons.badge_outlined, l10n.myProfile, onInsertProfileField, cs),
                  _toolBtn(Icons.check, l10n.markCheck, EditTool.check, cs),
                  _toolBtn(Icons.close, l10n.markCross, EditTool.cross, cs),
                  _toolBtn(Icons.check_box_outlined, l10n.markCheckbox, EditTool.checkbox, cs),
                  _toolBtn(Icons.fiber_manual_record, l10n.markDot, EditTool.dot, cs),
                  _toolBtn(Icons.remove, l10n.markDash, EditTool.dash, cs),
                  _toolBtn(Icons.title, l10n.toolText, EditTool.text, cs),
                  _toolBtn(Icons.edit, l10n.toolDraw, EditTool.draw, cs),
                  _toolBtn(Icons.highlight, l10n.toolHighlight, EditTool.highlight, cs),
                  _toolBtn(Icons.horizontal_rule, l10n.toolLine, EditTool.line, cs),
                  _toolBtn(Icons.north_east, l10n.toolArrow, EditTool.arrow, cs),
                  _toolBtn(Icons.crop_square, l10n.toolBox, EditTool.rect, cs),
                  _toolBtn(Icons.circle_outlined, l10n.toolOval, EditTool.oval, cs),
                  _toolBtn(Icons.format_color_fill, l10n.toolWhiteout, EditTool.whiteout, cs),
                  _toolBtn(Icons.cleaning_services, l10n.toolEraser, EditTool.eraser, cs),
                  _actionBtn(Icons.rotate_right, l10n.rotate, onRotatePage, cs),
                  _actionBtn(Icons.folder_open, l10n.toolOpen, onOpen, cs),
                ],
              ),
            ),
            if (showStyle)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 10, right: 10),
                child: Row(
                  children: [
                    ...[Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange, Colors.purple].map(
                      (c) => GestureDetector(
                        onTap: () => onColorChanged(c),
                        child: Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color == c ? cs.primary : Colors.grey.shade400,
                              width: color == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
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
                          min: 0.015,
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
