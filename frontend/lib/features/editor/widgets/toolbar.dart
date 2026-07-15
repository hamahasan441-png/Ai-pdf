import 'package:flutter/material.dart';
import '../models/annotation.dart';

class EditorToolbar extends StatelessWidget {
  final EditorTool active;
  final Color color;
  final double strokeWidth;
  final Function(EditorTool) onTool;
  final Function(Color) onColor;
  final Function(double) onStroke;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  const EditorToolbar({
    super.key, required this.active, required this.color,
    required this.strokeWidth, required this.onTool,
    required this.onColor, required this.onStroke,
    required this.onUndo, required this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Tools
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              _btn(Icons.pan_tool_alt, 'Select', EditorTool.select, cs),
              _btn(Icons.text_fields, 'Text', EditorTool.text, cs),
              _btn(Icons.highlight, 'Highlight', EditorTool.highlight, cs),
              _btn(Icons.draw, 'Draw', EditorTool.draw, cs),
              _btn(Icons.auto_fix_high, 'Eraser', EditorTool.eraser, cs),
              _btn(Icons.gesture, 'Sign', EditorTool.sign, cs),
              _btn(Icons.approval, 'Stamp', EditorTool.stamp, cs),
              _btn(Icons.crop_square, 'Shapes', EditorTool.shapes, cs),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.undo), onPressed: onUndo, tooltip: 'Undo'),
              IconButton(icon: const Icon(Icons.redo), onPressed: onRedo, tooltip: 'Redo'),
            ]),
          ),
          // Colors + stroke (for draw tools)
          if (active == EditorTool.draw || active == EditorTool.text || active == EditorTool.highlight || active == EditorTool.shapes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 12, right: 12),
              child: Row(children: [
                ...[Colors.black, Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.yellow]
                  .map((c) => GestureDetector(
                    onTap: () => onColor(c),
                    child: Container(width: 26, height: 26, margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                        border: Border.all(color: color == c ? cs.primary : Colors.grey.shade300, width: color == c ? 3 : 1))),
                  )),
                const Spacer(),
                SizedBox(width: 100, child: Slider(value: strokeWidth, min: 1, max: 20, onChanged: onStroke)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _btn(IconData icon, String label, EditorTool tool, ColorScheme cs) {
    final isActive = active == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => onTool(tool),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? cs.primaryContainer : null,
            borderRadius: BorderRadius.circular(8)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: isActive ? cs.primary : cs.onSurface),
            Text(label, style: TextStyle(fontSize: 9, color: isActive ? cs.primary : cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
