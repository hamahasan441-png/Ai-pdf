import 'package:flutter/material.dart';

/// Progressive loading overlay — E4.1 Enhancement-Based Masterplan.
///
/// Shows:
/// - Page count + % progress
/// - Current phase (rendering, OCR, indexing)
/// - Cancel button
/// - Low-RAM warning if applicable
class EditorLoadingOverlay extends StatelessWidget {
  final bool loading;
  final bool detecting;
  final String? detectingLabel;
  final int? pageCount;
  final int? currentPage; // 0-based
  final double? progress; // 0..1
  final VoidCallback? onCancel;
  final bool lowRamMode;

  const EditorLoadingOverlay({
    super.key,
    required this.loading,
    required this.detecting,
    this.detectingLabel,
    this.pageCount,
    this.currentPage,
    this.progress,
    this.onCancel,
    this.lowRamMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading && !detecting) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final hasProgress = progress != null && pageCount != null;
    final pct = hasProgress ? (progress! * 100).clamp(0, 100).toInt() : null;

    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x99000000),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: hasProgress ? progress : null,
                        strokeWidth: 5,
                      ),
                    ),
                    if (pct != null)
                      Text('$pct%',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: cs.primary)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  detecting
                      ? (detectingLabel ?? 'Analyzing document...')
                      : (pageCount != null
                          ? 'Opening ${pageCount!} pages...'
                          : 'Opening document...'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                if (currentPage != null && pageCount != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Page ${currentPage! + 1} / $pageCount',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
                if (detecting && detectingLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(detectingLabel!,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      textAlign: TextAlign.center),
                ],
                if (lowRamMode) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.memory, size: 14, color: cs.onErrorContainer),
                        const SizedBox(width: 6),
                        Text('Low-RAM mode: 900px cap',
                            style: TextStyle(
                                fontSize: 11, color: cs.onErrorContainer)),
                      ],
                    ),
                  ),
                ],
                if (onCancel != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel'),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'First page opens in <1.5s even for 1000-page PDFs. Thumbnails ±5 pre-render low-res then high-res (E4.1).',
                  style: TextStyle(fontSize: 10, color: cs.outline),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
