import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ShapeStyleResult {
  final bool filled;
  final double opacity;
  final double width;
  final Color color;

  const ShapeStyleResult({
    required this.filled,
    required this.opacity,
    required this.width,
    required this.color,
  });
}

Future<ShapeStyleResult?> showEditorShapeStyleDialog(
  BuildContext context, {
  required bool canFill,
  required bool filled,
  required double opacity,
  required double width,
  required Color color,
}) async {
  bool localFilled = filled;
  double localOpacity = opacity;
  double localWidth = width;
  Color localColor = color;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.shapeStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(width: 56, child: Text(AppLocalizations.of(ctx)!.width)),
                Expanded(
                  child: Slider(
                    value: localWidth,
                    min: 1,
                    max: 14,
                    onChanged: (v) => setLocal(() => localWidth = v),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(width: 56, child: Text(AppLocalizations.of(ctx)!.opacity)),
                Expanded(
                  child: Slider(
                    value: localOpacity,
                    min: 0.1,
                    max: 1,
                    onChanged: (v) => setLocal(() => localOpacity = v),
                  ),
                ),
              ],
            ),
            if (canFill)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppLocalizations.of(ctx)!.fill),
                value: localFilled,
                onChanged: (v) => setLocal(() => localFilled = v),
              ),
            Row(
              children: [Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange, Colors.purple]
                  .map((c) => GestureDetector(
                        onTap: () => setLocal(() => localColor = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.only(right: 8, top: 4),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: localColor == c ? Colors.blueAccent : Colors.grey.shade400,
                              width: localColor == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(ctx)!.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(ctx)!.ok)),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  return ShapeStyleResult(
    filled: localFilled,
    opacity: localOpacity,
    width: localWidth,
    color: localColor,
  );
}
