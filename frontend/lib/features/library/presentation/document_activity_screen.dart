import 'package:flutter/material.dart';

/// Document Activity Timeline — shows the history of actions performed on a
/// document: opens, edits, shares, exports, form fills, AI operations.
///
/// Each entry has: action type, timestamp, optional detail (e.g. "shared via Wi-Fi").
/// Useful for audit trails and tracking document lifecycle.
class DocumentActivityScreen extends StatelessWidget {
  final String documentName;
  final List<ActivityEntry> entries;

  const DocumentActivityScreen({
    super.key,
    required this.documentName,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('No activity yet'),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final entry = entries[i];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: entry.type.color.withOpacity(0.15),
                    child: Icon(entry.type.icon, size: 18, color: entry.type.color),
                  ),
                  title: Text(entry.type.label),
                  subtitle: entry.detail != null ? Text(entry.detail!) : null,
                  trailing: Text(
                    _formatTime(entry.timestamp),
                    style: theme.textTheme.bodySmall,
                  ),
                );
              },
            ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}

enum ActivityType {
  opened('Opened', Icons.folder_open, Colors.blue),
  edited('Edited', Icons.edit, Colors.orange),
  shared('Shared', Icons.share, Colors.green),
  exported('Exported', Icons.download, Colors.purple),
  formFilled('Form filled', Icons.check_circle, Colors.teal),
  aiChat('AI chat', Icons.smart_toy, Colors.indigo),
  signed('Signed', Icons.draw, Colors.brown),
  printed('Printed', Icons.print, Colors.grey);

  final String label;
  final IconData icon;
  final Color color;
  const ActivityType(this.label, this.icon, this.color);
}

class ActivityEntry {
  final ActivityType type;
  final DateTime timestamp;
  final String? detail;
  const ActivityEntry({required this.type, required this.timestamp, this.detail});
}
