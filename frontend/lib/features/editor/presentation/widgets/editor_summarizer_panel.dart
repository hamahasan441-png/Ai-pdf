import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_summarizer_controller.dart';

/// Panel showing the AI-generated document summary (Phase 50).
///
/// Displays: length selector, full summary text, key bullet points, and
/// per-section summaries with page links. "Regenerate" button for a new call
/// at a different length. Copy button for the full text.
class EditorSummarizerPanel extends StatelessWidget {
  final EditorSummarizerState summarizerState;
  final VoidCallback onGenerate;
  final ValueChanged<SummaryLength> onLengthChanged;
  final VoidCallback? onCopy;
  final ValueChanged<int>? onJumpToPage;
  final VoidCallback onClose;

  const EditorSummarizerPanel({
    super.key,
    required this.summarizerState,
    required this.onGenerate,
    required this.onLengthChanged,
    required this.onClose,
    this.onCopy,
    this.onJumpToPage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(12),
        bottomLeft: Radius.circular(12),
      ),
      color: cs.surface,
      child: SizedBox(
        width: 300,
        child: Column(
          children: [
            _header(cs),
            _lengthSelector(cs),
            const Divider(height: 1),
            Expanded(
              child: summarizerState.generating
                  ? const Center(child: CircularProgressIndicator())
                  : summarizerState.hasSummary
                      ? _content(cs)
                      : _empty(cs),
            ),
            if (summarizerState.error != null) _errorBanner(cs),
            _footer(cs),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.summarize, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Summary',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
          if (summarizerState.hasSummary) ...[
            const Spacer(),
            Text(
              '${summarizerState.wordCount} words',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ] else
            const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _lengthSelector(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SegmentedButton<SummaryLength>(
        segments: const [
          ButtonSegment(
              value: SummaryLength.brief,
              label: Text('Brief', style: TextStyle(fontSize: 11))),
          ButtonSegment(
              value: SummaryLength.standard,
              label: Text('Standard', style: TextStyle(fontSize: 11))),
          ButtonSegment(
              value: SummaryLength.detailed,
              label: Text('Detailed', style: TextStyle(fontSize: 11))),
        ],
        selected: {summarizerState.length},
        onSelectionChanged: (s) => onLengthChanged(s.first),
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
  }

  Widget _content(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Key points
        if (summarizerState.keyPoints.isNotEmpty) ...[
          Text('Key Points',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          for (final point in summarizerState.keyPoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('\u2022 ',
                      style: TextStyle(color: cs.primary, fontSize: 14)),
                  Expanded(
                    child: Text(point,
                        style: TextStyle(fontSize: 12, color: cs.onSurface)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
        // Full summary
        Text('Summary',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
        const SizedBox(height: 6),
        Text(
          summarizerState.fullSummary!,
          style: TextStyle(fontSize: 12, color: cs.onSurface, height: 1.5),
        ),
        // Sections
        if (summarizerState.sections.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          for (final section in summarizerState.sections) ...[
            InkWell(
              onTap: section.pageStart != null
                  ? () => onJumpToPage?.call(section.pageStart!)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(section.heading,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.primary)),
                      ),
                      if (section.pageStart != null)
                        Text(
                          'p.${section.pageStart! + 1}${section.pageEnd != null ? '-${section.pageEnd! + 1}' : ''}',
                          style: TextStyle(
                              fontSize: 10, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(section.content,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _empty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome,
              size: 48, color: cs.primary.withOpacity(0.3)),
          const SizedBox(height: 8),
          Text('Generate a summary of this document',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _errorBanner(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: cs.errorContainer,
      child: Text(
        summarizerState.error!,
        style: TextStyle(fontSize: 11, color: cs.onErrorContainer),
      ),
    );
  }

  Widget _footer(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          if (onCopy != null && summarizerState.hasSummary)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: onCopy,
              tooltip: 'Copy summary',
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          const Spacer(),
          FilledButton.icon(
            icon: Icon(
                summarizerState.hasSummary ? Icons.refresh : Icons.auto_awesome,
                size: 16),
            label: Text(
              summarizerState.hasSummary ? 'Regenerate' : 'Generate',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: summarizerState.generating ? null : onGenerate,
          ),
        ],
      ),
    );
  }
}
