import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_pdf/features/viewer/presentation/reading_mode_controller.dart';

const _prefsKey = 'editor_reading_mode';

/// The reading mode chosen last time, or normal.
Future<ReadingMode> loadEditorReadingMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefsKey);
    return ReadingMode.values.firstWhere((m) => m.name == name, orElse: () => ReadingMode.normal);
  } catch (e) {
    debugPrint('Reading mode not loaded: $e');
    return ReadingMode.normal;
  }
}

Future<void> saveEditorReadingMode(ReadingMode mode) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  } catch (e) {
    debugPrint('Reading mode not saved: $e');
  }
}

/// Lets the user pick how pages look on screen. Returns null if dismissed.
Future<ReadingMode?> showEditorReadingModeSheet(BuildContext context, {required ReadingMode current}) {
  final l10n = AppLocalizations.of(context)!;
  String label(ReadingMode m) => switch (m) {
        ReadingMode.normal => l10n.readingModeNormal,
        ReadingMode.dark => l10n.readingModeDark,
        ReadingMode.sepia => l10n.readingModeSepia,
        ReadingMode.green => l10n.readingModeGreen,
      };
  IconData icon(ReadingMode m) => switch (m) {
        ReadingMode.normal => Icons.light_mode_outlined,
        ReadingMode.dark => Icons.dark_mode_outlined,
        ReadingMode.sepia => Icons.coffee_outlined,
        ReadingMode.green => Icons.eco_outlined,
      };
  return showModalBottomSheet<ReadingMode>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(l10n.toolReadingMode, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(l10n.readingModeNote, style: Theme.of(ctx).textTheme.bodySmall),
          ),
          for (final m in ReadingMode.values)
            ListTile(
              leading: Icon(icon(m)),
              title: Text(label(m)),
              trailing: m == current ? const Icon(Icons.check) : null,
              selected: m == current,
              onTap: () => Navigator.pop(ctx, m),
            ),
        ],
      ),
    ),
  );
}
