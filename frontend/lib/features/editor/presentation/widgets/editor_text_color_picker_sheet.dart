import 'package:flutter/material.dart';

Future<Color?> showEditorTextColorPickerSheet(
  BuildContext context, {
  required Color selectedColor,
}) {
  const swatches = <Color>[
    Color(0xFF1B2130),
    Colors.black,
    Color(0xFF4C63D2),
    Color(0xFF2E9E7B),
    Color(0xFFD9636B),
    Color(0xFFCF9A4E),
    Color(0xFF7E7BD4),
    Colors.white,
  ];

  return showModalBottomSheet<Color>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Text colour', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final c in swatches)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selectedColor == c ? Colors.blueAccent : Colors.black26,
                          width: selectedColor == c ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
