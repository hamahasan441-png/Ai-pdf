import 'package:flutter/material.dart';

import 'package:ai_pdf/features/viewer/presentation/reading_mode_controller.dart';

/// Bottom sheet for reading experience settings.
///
/// Controls: reading mode (normal/dark/sepia/green), brightness overlay,
/// continuous scroll toggle, thumbnail strip toggle, auto-scroll.
class ReadingModeSheet extends StatelessWidget {
  final ReadingModeState state;
  final ReadingModeController controller;

  const ReadingModeSheet({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Reading Mode', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),

            // Mode chips
            Wrap(
              spacing: 8,
              children: ReadingMode.values.map((mode) {
                final label = switch (mode) {
                  ReadingMode.normal => 'Normal',
                  ReadingMode.dark => 'Dark',
                  ReadingMode.sepia => 'Sepia',
                  ReadingMode.green => 'Eye comfort',
                };
                final icon = switch (mode) {
                  ReadingMode.normal => Icons.brightness_high,
                  ReadingMode.dark => Icons.dark_mode,
                  ReadingMode.sepia => Icons.auto_stories,
                  ReadingMode.green => Icons.visibility,
                };
                return ChoiceChip(
                  selected: state.mode == mode,
                  label: Text(label),
                  avatar: Icon(icon, size: 18),
                  onSelected: (_) => controller.setMode(mode),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Brightness slider
            Text('Brightness', style: theme.textTheme.labelMedium),
            Slider(
              value: state.brightness,
              min: 0.1,
              max: 1.0,
              onChanged: controller.setBrightness,
            ),
            const SizedBox(height: 8),

            // Toggles
            SwitchListTile(
              title: const Text('Continuous scroll'),
              subtitle: const Text('Scroll through all pages vertically'),
              value: state.continuousScroll,
              onChanged: (_) => controller.toggleContinuousScroll(),
            ),
            SwitchListTile(
              title: const Text('Page thumbnails'),
              subtitle: const Text('Show mini page strip for navigation'),
              value: state.showThumbnails,
              onChanged: (_) => controller.toggleThumbnails(),
            ),
            SwitchListTile(
              title: const Text('Auto-scroll'),
              subtitle: const Text('Hands-free reading'),
              value: state.autoScroll,
              onChanged: (_) => controller.toggleAutoScroll(),
            ),
            if (state.autoScroll) ...[
              Text('Scroll speed', style: theme.textTheme.labelMedium),
              Slider(
                value: state.autoScrollSpeed,
                min: 10,
                max: 200,
                divisions: 19,
                label: '${state.autoScrollSpeed.round()} px/s',
                onChanged: controller.setAutoScrollSpeed,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
