import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ProfileValueOption {
  final String key;
  final String label;
  final String value;

  const ProfileValueOption({
    required this.key,
    required this.label,
    required this.value,
  });
}

Future<ProfileValueOption?> showEditorProfileFieldPickerSheet(
  BuildContext context, {
  required List<ProfileValueOption> entries,
  required VoidCallback onSetUpProfile,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<ProfileValueOption>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      if (entries.isEmpty) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.badge_outlined, size: 48, color: Theme.of(ctx).colorScheme.outline),
                const SizedBox(height: 12),
                Text(l10n.noProfileData, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onSetUpProfile();
                  },
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(l10n.setUpProfile),
                ),
              ],
            ),
          ),
        );
      }
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in entries)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(entry.value),
                subtitle: Text(entry.label),
                onTap: () => Navigator.pop(ctx, entry),
              ),
          ],
        ),
      );
    },
  );
}
