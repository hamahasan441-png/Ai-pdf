import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class EditorEmptyState extends StatelessWidget {
  final bool loading;
  final VoidCallback onPick;

  const EditorEmptyState({
    super.key,
    required this.loading,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.draw_outlined, size: 72, color: Colors.white38),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.openPdfOrImageToEdit,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: loading ? null : onPick,
            icon: const Icon(Icons.folder_open),
            label: Text(AppLocalizations.of(context)!.chooseFile),
          ),
        ],
      ),
    );
  }
}
