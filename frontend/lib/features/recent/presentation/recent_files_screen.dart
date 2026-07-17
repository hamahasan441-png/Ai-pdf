import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/services/recent_files_service.dart';
import '../../tools/services/output_actions.dart';
import '../../tools/widgets/result_sheet.dart';

/// Shows every file the app has created / edited / saved, newest first.
/// Each entry can be previewed, saved, shared, or removed from the list.
class RecentFilesScreen extends StatefulWidget {
  const RecentFilesScreen({super.key});

  @override
  State<RecentFilesScreen> createState() => _RecentFilesScreenState();
}

class _RecentFilesScreenState extends State<RecentFilesScreen> {
  @override
  void initState() {
    super.initState();
    RecentFilesService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.recentFiles),
        actions: [
          ValueListenableBuilder<List<RecentFile>>(
            valueListenable: RecentFilesService.instance.notifier,
            builder: (_, items, __) => items.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: l10n.clearList,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _confirmClear(context),
                  ),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<RecentFile>>(
        valueListenable: RecentFilesService.instance.notifier,
        builder: (_, items, __) {
          if (items.isEmpty) return _empty(cs);
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _RecentTile(file: items[i]),
          );
        },
      ),
    );
  }

  Widget _empty(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(Icons.history, size: 48, color: cs.outline),
          ),
          const SizedBox(height: 20),
          Text(l10n.noRecentFiles,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(l10n.noRecentFilesBody, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearRecentTitle),
        content: Text(l10n.clearRecentBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.clear)),
        ],
      ),
    );
    if (ok == true) await RecentFilesService.instance.clear();
  }
}

class _RecentTile extends StatelessWidget {
  final RecentFile file;
  const _RecentTile({required this.file});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final when = DateFormat('MMM d, h:mm a').format(file.date);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListTile(
        onTap: () => _preview(context),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (file.isPdf ? Colors.red : Colors.blue).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(file.isPdf ? Icons.picture_as_pdf : Icons.image,
              color: file.isPdf ? Colors.red : Colors.blue),
        ),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${file.action}  •  $when',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _onAction(context, v),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'preview', child: Row(children: [const Icon(Icons.visibility_outlined), const SizedBox(width: 10), Text(l10n.preview)])),
            PopupMenuItem(value: 'save', child: Row(children: [const Icon(Icons.download_outlined), const SizedBox(width: 10), Text(l10n.save)])),
            PopupMenuItem(value: 'share', child: Row(children: [const Icon(Icons.share_outlined), const SizedBox(width: 10), Text(l10n.share)])),
            PopupMenuItem(value: 'remove', child: Row(children: [const Icon(Icons.close), const SizedBox(width: 10), Text(l10n.remove)])),
          ],
        ),
      ),
    );
  }

  void _onAction(BuildContext context, String value) {
    switch (value) {
      case 'preview':
        _preview(context);
        break;
      case 'save':
        OutputActions.save(context, file.path);
        break;
      case 'share':
        OutputActions.share(context, file.path);
        break;
      case 'remove':
        RecentFilesService.instance.remove(file.path);
        break;
    }
  }

  void _preview(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FilePreviewScreen(path: file.path, isPdf: file.isPdf),
    ));
  }
}
