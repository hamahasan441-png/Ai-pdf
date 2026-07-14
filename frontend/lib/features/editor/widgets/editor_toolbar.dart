import 'package:flutter/material.dart';
import '../models/annotation.dart';

/// Professional PDF editor toolbar
class EditorToolbar extends StatelessWidget {
  final EditorTool activeTool;
  final Color activeColor;
  final double strokeWidth;
  final Function(EditorTool) onToolChanged;
  final Function(Color) onColorChanged;
  final Function(double) onStrokeWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSave;

  const EditorToolbar({
    super.key,
    required this.activeTool,
    required this.activeColor,
    required this.strokeWidth,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main tools row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ToolButton(
                    icon: Icons.pan_tool_alt_outlined,
                    label: 'Select',
                    isActive: activeTool == EditorTool.select,
                    onTap: () => onToolChanged(EditorTool.select),
                  ),
                  _ToolButton(
                    icon: Icons.text_fields,
                    label: 'Text',
                    isActive: activeTool == EditorTool.text,
                    onTap: () => onToolChanged(EditorTool.text),
                  ),
                  _ToolButton(
                    icon: Icons.highlight,
                    label: 'Highlight',
                    isActive: activeTool == EditorTool.highlight,
                    onTap: () => onToolChanged(EditorTool.highlight),
                  ),
                  _ToolButton(
                    icon: Icons.draw,
                    label: 'Draw',
                    isActive: activeTool == EditorTool.freehand,
                    onTap: () => onToolChanged(EditorTool.freehand),
                  ),
                  _ToolButton(
                    icon: Icons.auto_fix_high,
                    label: 'Eraser',
                    isActive: activeTool == EditorTool.eraser,
                    onTap: () => onToolChanged(EditorTool.eraser),
                  ),
                  _ToolButton(
                    icon: Icons.draw_outlined,
                    label: 'Sign',
                    isActive: activeTool == EditorTool.signature,
                    onTap: () => onToolChanged(EditorTool.signature),
                  ),
                  _ToolButton(
                    icon: Icons.approval,
                    label: 'Stamp',
                    isActive: activeTool == EditorTool.stamp,
                    onTap: () => onToolChanged(EditorTool.stamp),
                  ),
                  const VerticalDivider(width: 16),
                  IconButton(
                    icon: const Icon(Icons.undo),
                    onPressed: onUndo,
                    tooltip: 'Undo',
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo),
                    onPressed: onRedo,
                    tooltip: 'Redo',
                  ),
                  const VerticalDivider(width: 16),
                  IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: onSave,
                    tooltip: 'Save',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
            // Color & stroke row (shown for drawing tools)
            if (activeTool == EditorTool.freehand ||
                activeTool == EditorTool.text ||
                activeTool == EditorTool.highlight)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    // Color picker
                    ...[
                      Colors.black,
                      Colors.red,
                      Colors.blue,
                      Colors.green,
                      Colors.orange,
                      Colors.purple,
                      Colors.yellow,
                    ].map((color) => GestureDetector(
                      onTap: () => onColorChanged(color),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: activeColor == color
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                            width: activeColor == color ? 3 : 1,
                          ),
                        ),
                      ),
                    )),
                    const Spacer(),
                    // Stroke width
                    SizedBox(
                      width: 120,
                      child: Slider(
                        value: strokeWidth,
                        min: 1,
                        max: 20,
                        onChanged: onStrokeWidthChanged,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 10, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
