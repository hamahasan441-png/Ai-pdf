import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Continuous vertical scroll viewer — displays all PDF pages in a single
/// scrollable column instead of one page at a time.
///
/// Performance: uses a lazy [ListView.builder] so only visible pages (plus a
/// small buffer) are rendered/cached in memory. Pages outside the viewport are
/// disposed and re-rendered on scroll-back.
///
/// This is the "web-like" reading experience users expect from Chrome PDF viewer
/// and mobile apps like Google Drive.
class ContinuousScrollViewer extends StatelessWidget {
  final int pageCount;
  final double pageWidth;
  final double pageHeight;
  final List<Uint8List?> pageImages; // Rendered pages (null = not yet rendered)
  final ValueChanged<int> onPageVisible; // Called when a new page scrolls into view
  final ScrollController? scrollController;

  const ContinuousScrollViewer({
    super.key,
    required this.pageCount,
    required this.pageWidth,
    required this.pageHeight,
    required this.pageImages,
    required this.onPageVisible,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          // Calculate which page is most visible based on scroll position.
          final offset = notification.metrics.pixels;
          final pageHeightWithGap = pageHeight + 12; // 12px gap between pages
          final visiblePage = (offset / pageHeightWithGap).floor().clamp(0, pageCount - 1);
          onPageVisible(visiblePage);
        }
        return false;
      },
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: pageCount,
        itemBuilder: (context, index) {
          final image = index < pageImages.length ? pageImages[index] : null;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: AspectRatio(
              aspectRatio: pageWidth / pageHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: image != null
                    ? Image.memory(image, fit: BoxFit.contain)
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(strokeWidth: 2),
                            const SizedBox(height: 8),
                            Text(
                              'Page ${index + 1}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
