import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/detected_field.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_canvas_painter.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_selection_overlay.dart';

class EditorCanvas extends StatelessWidget {
  final Uint8List bytes;
  final EditTool tool;
  final PageLayer layer;
  final List<Offset> drawing;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final ShapeType? previewShapeType;
  final Color color;
  final double stroke;
  final bool highlightPreview;
  final bool showFields;
  final List<DetectedField> pageFields;
  final bool showEditLines;
  final List<OcrLine> editLines;
  final double? guideX;
  final double? guideY;
  final Set<EditorAnnotation> multi;
  final String selMode;
  final Offset? marqueeStart;
  final Offset? marqueeEnd;
  final EditorAnnotation? selected;
  final Rect Function(EditorAnnotation) boundsOf;
  final void Function(Offset localPosition, Size canvasSize) onTapUp;
  final void Function(Offset localPosition, Size canvasSize) onPanStart;
  final void Function(Offset localPosition, Size canvasSize) onPanUpdate;
  final VoidCallback onPanEnd;
  final void Function(DetectedField field) onFieldTap;
  final void Function(OcrLine line) onEditLineTap;
  final void Function(TextAnnotation text) onEditText;
  final void Function(TextAnnotation text) onSelectText;
  final void Function(TextAnnotation text, DragUpdateDetails details, Size canvasSize) onMoveText;
  final void Function(Rect nextBounds) onResizeBounds;

  /// Drag lifecycle hooks so a whole move / resize becomes one undo step.
  final void Function(TextAnnotation text)? onMoveTextStart;
  final VoidCallback? onMoveTextEnd;
  final VoidCallback? onResizeStart;
  final VoidCallback? onResizeEnd;
  final VoidCallback onTextDecrease;
  final VoidCallback onTextIncrease;
  final VoidCallback onPickTextColor;
  final VoidCallback onEditShapeStyle;
  final VoidCallback onCopySelected;
  final VoidCallback onDuplicateSelected;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback onDeleteSelected;
  final VoidCallback onDeselectSelected;
  final void Function(String how) onAlignMulti;
  final void Function(Axis axis) onDistributeMulti;
  final VoidCallback onDuplicateMulti;
  final VoidCallback onDeleteMulti;
  final VoidCallback onDeselectMulti;
  final IconData Function(FieldType type) resolveTypeIcon;

  const EditorCanvas({
    super.key,
    required this.bytes,
    required this.tool,
    required this.layer,
    required this.drawing,
    required this.shapeStart,
    required this.shapeEnd,
    required this.previewShapeType,
    required this.color,
    required this.stroke,
    required this.highlightPreview,
    required this.showFields,
    required this.pageFields,
    required this.showEditLines,
    required this.editLines,
    required this.guideX,
    required this.guideY,
    required this.multi,
    required this.selMode,
    required this.marqueeStart,
    required this.marqueeEnd,
    required this.selected,
    required this.boundsOf,
    required this.onTapUp,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onFieldTap,
    required this.onEditLineTap,
    required this.onEditText,
    required this.onSelectText,
    required this.onMoveText,
    required this.onResizeBounds,
    this.onMoveTextStart,
    this.onMoveTextEnd,
    this.onResizeStart,
    this.onResizeEnd,
    required this.onTextDecrease,
    required this.onTextIncrease,
    required this.onPickTextColor,
    required this.onEditShapeStyle,
    required this.onCopySelected,
    required this.onDuplicateSelected,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onDeleteSelected,
    required this.onDeselectSelected,
    required this.onAlignMulti,
    required this.onDistributeMulti,
    required this.onDuplicateMulti,
    required this.onDeleteMulti,
    required this.onDeselectMulti,
    required this.resolveTypeIcon,
  });

  bool get _canDragText => tool == EditTool.pan || tool == EditTool.text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapUp: (d) => onTapUp(d.localPosition, size),
          onPanStart: (d) => onPanStart(d.localPosition, size),
          onPanUpdate: (d) => onPanUpdate(d.localPosition, size),
          onPanEnd: (_) => onPanEnd(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true),
              CustomPaint(
                painter: EditorCanvasPainter(
                  layer.strokes,
                  layer.shapes,
                  drawing,
                  shapeStart,
                  shapeEnd,
                  previewShapeType,
                  color,
                  stroke,
                  highlightPreview,
                ),
              ),
              if (showFields) ...pageFields.map((f) {
                final isCheckbox = f.type == FieldType.checkbox;
                final isRadio = f.type == FieldType.radio;
                final base = isCheckbox
                    ? Colors.green
                    : isRadio
                        ? Colors.blue
                        : Colors.amber;
                return Positioned(
                  left: f.rect.left * size.width,
                  top: f.rect.top * size.height,
                  child: GestureDetector(
                    onTap: () => onFieldTap(f),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 18),
                      width: isCheckbox || isRadio
                          ? (f.rect.width * size.width).clamp(18.0, 40.0)
                          : null,
                      height: (f.rect.height * size.height).clamp(18.0, 60.0),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: base.withOpacity(0.18),
                        border: Border.all(color: base.shade700, width: 1.5),
                        borderRadius: isRadio ? BorderRadius.circular(100) : BorderRadius.circular(4),
                      ),
                      child: Icon(resolveTypeIcon(f.type), size: 14, color: base.shade900),
                    ),
                  ),
                );
              }),
              if (showEditLines)
                ...editLines.map((line) => Positioned(
                      left: line.x * size.width,
                      top: line.y * size.height,
                      width: (line.w * size.width).clamp(10.0, size.width),
                      height: (line.h * size.height).clamp(12.0, 80.0),
                      child: GestureDetector(
                        onTap: () => onEditLineTap(line),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.14),
                            border: Border.all(color: Colors.blueAccent, width: 1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    )),
              if (guideX != null)
                Positioned(
                  left: guideX! * size.width,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(child: Container(width: 1, color: Colors.pinkAccent)),
                ),
              if (guideY != null)
                Positioned(
                  top: guideY! * size.height,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: Container(height: 1, color: Colors.pinkAccent)),
                ),
              ...multi.map((a) {
                final r = boundsOf(a);
                return Positioned(
                  left: r.left * size.width,
                  top: r.top * size.height,
                  width: (r.width * size.width).clamp(6.0, size.width),
                  height: (r.height * size.height).clamp(6.0, size.height),
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue, width: 1.5),
                        color: Colors.blue.withOpacity(0.08),
                      ),
                    ),
                  ),
                );
              }),
              if (selMode == 'marquee' && marqueeStart != null && marqueeEnd != null)
                Positioned.fromRect(
                  rect: Rect.fromPoints(
                    Offset(marqueeStart!.dx * size.width, marqueeStart!.dy * size.height),
                    Offset(marqueeEnd!.dx * size.width, marqueeEnd!.dy * size.height),
                  ),
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blueAccent),
                        color: Colors.blue.withOpacity(0.12),
                      ),
                    ),
                  ),
                ),
              ...layer.texts.map((t) => Positioned(
                    left: t.pos.dx * size.width,
                    top: t.pos.dy * size.height,
                    child: GestureDetector(
                      onTap: () {
                        if (tool == EditTool.pan) {
                          onSelectText(t);
                        } else {
                          onEditText(t);
                        }
                      },
                      onPanStart: _canDragText
                          ? (_) => onMoveTextStart?.call(t)
                          : null,
                      onPanUpdate: _canDragText ? (d) => onMoveText(t, d, size) : null,
                      onPanEnd: _canDragText ? (_) => onMoveTextEnd?.call() : null,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          border: selected == t ? Border.all(color: Colors.blue, width: 2) : null,
                        ),
                        child: Text(
                          t.text,
                          style: TextStyle(
                            color: t.color,
                            fontSize: t.size * size.height,
                            fontWeight: t.bold ? FontWeight.w800 : FontWeight.w500,
                            fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
                            decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
                            decorationColor: t.color,
                            fontFamily: t.fontFamily,
                          ),
                        ),
                      ),
                    ),
                  )),
              if (selected != null) ...[
                EditorSelectionBox(size: size, bounds: boundsOf(selected!)),
                EditorScaleHandle(
                  size: size,
                  bounds: boundsOf(selected!),
                  bottomRight: false,
                  onResizeBounds: onResizeBounds,
                  onResizeStart: onResizeStart,
                  onResizeEnd: onResizeEnd,
                ),
                EditorScaleHandle(
                  size: size,
                  bounds: boundsOf(selected!),
                  bottomRight: true,
                  onResizeBounds: onResizeBounds,
                  onResizeStart: onResizeStart,
                  onResizeEnd: onResizeEnd,
                ),
              ],
              if (selected != null)
                EditorSelectionActionBar(
                  showTextActions: selected is TextAnnotation,
                  showShapeActions: selected is ShapeAnnotation,
                  onEditText: selected is TextAnnotation ? () => onEditText(selected! as TextAnnotation) : null,
                  onTextDecrease: selected is TextAnnotation ? onTextDecrease : null,
                  onTextIncrease: selected is TextAnnotation ? onTextIncrease : null,
                  onPickTextColor: selected is TextAnnotation ? onPickTextColor : null,
                  onEditShapeStyle: selected is ShapeAnnotation ? onEditShapeStyle : null,
                  onCopy: onCopySelected,
                  onDuplicate: onDuplicateSelected,
                  onBringToFront: onBringToFront,
                  onSendToBack: onSendToBack,
                  onDelete: onDeleteSelected,
                  onDeselect: onDeselectSelected,
                ),
              if (multi.isNotEmpty)
                EditorMultiSelectionActionBar(
                  count: multi.length,
                  onAlignLeft: () => onAlignMulti('left'),
                  onAlignCenter: () => onAlignMulti('hcenter'),
                  onAlignRight: () => onAlignMulti('right'),
                  onAlignTop: () => onAlignMulti('top'),
                  onAlignMiddle: () => onAlignMulti('vcenter'),
                  onAlignBottom: () => onAlignMulti('bottom'),
                  onDistributeH: () => onDistributeMulti(Axis.horizontal),
                  onDistributeV: () => onDistributeMulti(Axis.vertical),
                  onDuplicate: onDuplicateMulti,
                  onDelete: onDeleteMulti,
                  onDeselect: onDeselectMulti,
                ),
            ],
          ),
        );
      },
    );
  }
}
