import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';

/// A horizontally scrollable strip of page thumbnails for quick navigation
/// and page management (tap to jump, long-press for delete/duplicate).
///
/// Sits above the main toolbar. Each thumbnail shows a scaled-down version of
/// the rendered page (from the cache), with the current page highlighted.
class EditorPageThumbnailStrip extends StatelessWidget {
  final int pageCount;
  final int currentPage;
  final Map<int, Uint8List> pageCache;
  final ValueChanged<int> onPageTap;
  final void Function(int index, String action)? onPageAction;

  const EditorPageThumbnailStrip({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.pageCache,
    required this.onPageTap,
    this.onPageAction,
  });

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();
    final palette = EditorPalette.of(context);
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: palette.barSurface,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        itemCount: pageCount,
        itemBuilder: (context, index) {
          final isCurrent = index == currentPage;
          final bytes = pageCache[index];
          return GestureDetector(
            onTap: () => onPageTap(index),
            onLongPress: onPageAction == null ? null : () => _showActions(context, index),
            child: Container(
              width: 52,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isCurrent ? palette.accent : palette.hairline,
                  width: isCurrent ? 2.5 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
                color: palette.fieldSurface,
                boxShadow: isCurrent ? EditorChrome.floatShadow(palette.brightness) : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (bytes != null)
                      Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        // Thumbs are ~52px. Decoding the 2400px page bitmap
                        // here blows the image cache and janks the editor.
                        cacheWidth: 120,
                        filterQuality: FilterQuality.low,
                      )
                    else
                      ColoredBox(color: palette.canvasBackground),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        color: isCurrent ? palette.accent : const Color(0x99000000),
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isCurrent ? palette.onAccent : Colors.white,
                          ),
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

  void _showActions(BuildContext context, int index) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(EditorChrome.radiusSheet))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(l10n.pageDuplicate),
              onTap: () {
                Navigator.pop(ctx);
                onPageAction?.call(index, 'duplicate');
              },
            ),
            if (index > 0)
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: Text(l10n.pageMoveEarlier),
                onTap: () {
                  Navigator.pop(ctx);
                  onPageAction?.call(index, 'moveEarlier');
                },
              ),
            if (index < pageCount - 1)
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: Text(l10n.pageMoveLater),
                onTap: () {
                  Navigator.pop(ctx);
                  onPageAction?.call(index, 'moveLater');
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.pageInsertBlankAfter),
              onTap: () {
                Navigator.pop(ctx);
                onPageAction?.call(index, 'insert');
              },
            ),
            if (pageCount > 1)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text(l10n.pageDelete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  onPageAction?.call(index, 'delete');
                },
              ),
          ],
        ),
      ),
    );
  }
}
