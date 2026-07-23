import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Horizontal thumbnail strip for quick page navigation.
///
/// Shows mini-rendered page previews at the bottom or side of the viewer.
/// Tapping a thumbnail jumps to that page. The current page is highlighted.
class PageThumbnailsStrip extends StatelessWidget {
  final int pageCount;
  final int currentPage;
  final ValueChanged<int> onPageSelected;
  final List<Uint8List?> thumbnails; // Pre-rendered thumbnails (nullable = loading)

  const PageThumbnailsStrip({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.onPageSelected,
    required this.thumbnails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: pageCount,
        itemBuilder: (context, index) {
          final isActive = index == currentPage;
          final thumb = index < thumbnails.length ? thumbnails[index] : null;
          return GestureDetector(
            onTap: () => onPageSelected(index),
            child: Container(
              width: 60,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isActive ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                  width: isActive ? 2.5 : 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb != null)
                      Image.memory(thumb, fit: BoxFit.cover)
                    else
                      Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                    // Page number badge
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
