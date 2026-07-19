import 'package:flutter/material.dart';

Future<String?> showEditorMarkChoiceSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            _MarkChoice(mark: '✓', label: 'Correct', color: Color(0xFF16A34A)),
            _MarkChoice(mark: '✗', label: 'Wrong', color: Color(0xFFD9636B)),
          ],
        ),
      ),
    ),
  );
}

class _MarkChoice extends StatelessWidget {
  final String mark;
  final String label;
  final Color color;

  const _MarkChoice({
    required this.mark,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(context, mark),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  mark,
                  style: TextStyle(fontSize: 36, color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
