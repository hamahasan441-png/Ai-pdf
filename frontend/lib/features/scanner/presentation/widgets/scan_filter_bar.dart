import 'package:flutter/material.dart';

import 'package:ai_pdf/features/scanner/domain/entities/scan_filter.dart';

/// Horizontal selector for the scan enhancement filter (Phase 51).
class ScanFilterBar extends StatelessWidget {
  final ScanFilter selected;
  final ValueChanged<ScanFilter> onSelected;

  const ScanFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Colors.black.withOpacity(0.6),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final f in ScanFilter.values) _chip(f, cs),
          ],
        ),
      ),
    );
  }

  Widget _chip(ScanFilter filter, ColorScheme cs) {
    final active = filter == selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => onSelected(filter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active ? cs.primaryContainer : Colors.white24,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? cs.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Icon(
                _iconFor(filter),
                color: active ? cs.primary : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              filter.label,
              style: TextStyle(
                fontSize: 10,
                color: active ? cs.primary : Colors.white,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(ScanFilter filter) {
    switch (filter) {
      case ScanFilter.original:
        return Icons.image;
      case ScanFilter.auto:
        return Icons.auto_fix_high;
      case ScanFilter.grayscale:
        return Icons.gradient;
      case ScanFilter.blackWhite:
        return Icons.contrast;
      case ScanFilter.photo:
        return Icons.photo_camera_back;
    }
  }
}
