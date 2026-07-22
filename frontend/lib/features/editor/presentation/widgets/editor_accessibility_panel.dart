import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_accessibility_controller.dart';

/// Panel showing accessibility audit results (Phase 37).
///
/// Displays a summary header (error/warning/info counts), a scrollable list of
/// issues with severity icons and suggested fixes, and a "Re-scan" button.
/// Tapping an issue jumps to the related page/annotation.
class EditorAccessibilityPanel extends StatelessWidget {
  final EditorAccessibilityState accessibilityState;
  final VoidCallback onRescan;
  final VoidCallback onClose;
  final void Function(int page, String? annotationId)? onIssueTap;

  const EditorAccessibilityPanel({
    super.key,
    required this.accessibilityState,
    required this.onRescan,
    required this.onClose,
    this.onIssueTap,
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
        width: 280,
        child: Column(
          children: [
            _header(cs),
            _summary(cs),
            const Divider(height: 1),
            Expanded(
              child: accessibilityState.isClean
                  ? _cleanState(cs)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: accessibilityState.issues.length,
                      itemBuilder: (_, i) =>
                          _issueRow(accessibilityState.issues[i], cs),
                    ),
            ),
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
          Icon(Icons.accessibility_new, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Accessibility',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
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

  Widget _summary(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _badge('${accessibilityState.errorCount}', Colors.red, cs),
          const SizedBox(width: 6),
          _badge('${accessibilityState.warningCount}', Colors.orange, cs),
          const SizedBox(width: 6),
          _badge('${accessibilityState.infoCount}', Colors.blue, cs),
          const Spacer(),
          Text(
            '${accessibilityState.totalCount} issues',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _cleanState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 48, color: Colors.green.shade400),
          const SizedBox(height: 8),
          Text('No issues found!',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _issueRow(A11yIssue issue, ColorScheme cs) {
    return InkWell(
      onTap: () => onIssueTap?.call(issue.pageIndex ?? 0, issue.annotationId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_severityIcon(issue.severity),
                size: 18, color: _severityColor(issue.severity)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(issue.message,
                      style: TextStyle(fontSize: 12, color: cs.onSurface)),
                  if (issue.fix != null)
                    Text(issue.fix!,
                        style: TextStyle(fontSize: 11, color: cs.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Re-scan', style: TextStyle(fontSize: 12)),
        onPressed: accessibilityState.scanning ? null : onRescan,
      ),
    );
  }

  IconData _severityIcon(A11ySeverity s) {
    switch (s) {
      case A11ySeverity.error:
        return Icons.error;
      case A11ySeverity.warning:
        return Icons.warning;
      case A11ySeverity.info:
        return Icons.info;
    }
  }

  Color _severityColor(A11ySeverity s) {
    switch (s) {
      case A11ySeverity.error:
        return Colors.red;
      case A11ySeverity.warning:
        return Colors.orange;
      case A11ySeverity.info:
        return Colors.blue;
    }
  }
}
