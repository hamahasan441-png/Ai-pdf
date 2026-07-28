import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom sheet that displays OCR-extracted text from scanned pages with
/// copy and re-scan action buttons.
class ScanTextResultSheet extends StatelessWidget {
  final String text;
  final VoidCallback? onRescan;

  const ScanTextResultSheet({
    super.key,
    required this.text,
    this.onRescan,
  });

  /// Show this sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String text,
    VoidCallback? onRescan,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ScanTextResultSheet(text: text, onRescan: onRescan),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header with actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.text_snippet, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Extracted Text',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (onRescan != null)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Re-scan OCR',
                      onPressed: () {
                        Navigator.pop(context);
                        onRescan!();
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy all',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            // Text content
            Expanded(
              child: text.isEmpty
                  ? Center(
                      child: Text(
                        'No text detected',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        text,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
