import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_ocr_settings_controller.dart';

/// Bottom sheet for configuring OCR languages and options (Phase 45).
///
/// Multi-select language chips (downloaded ones highlighted), engine picker,
/// and preprocessing toggles (contrast boost, deskew). Download buttons for
/// unavailable language packs.
class EditorOcrSettingsSheet extends StatelessWidget {
  final EditorOcrSettingsState ocrState;
  final ValueChanged<String> onToggleLanguage;
  final ValueChanged<String>? onDownloadLanguage;
  final ValueChanged<bool> onAutoDetectChanged;
  final ValueChanged<OcrEngine> onEngineChanged;
  final ValueChanged<bool> onContrastChanged;
  final ValueChanged<bool> onDeskewChanged;
  final VoidCallback onClose;

  const EditorOcrSettingsSheet({
    super.key,
    required this.ocrState,
    required this.onToggleLanguage,
    required this.onAutoDetectChanged,
    required this.onEngineChanged,
    required this.onContrastChanged,
    required this.onDeskewChanged,
    required this.onClose,
    this.onDownloadLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(cs),
            const SizedBox(height: 12),
            Text('Active Languages',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            _languageChips(ocrState.downloadedLanguages, cs),
            if (ocrState.availableLanguages.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Available (download)',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              _downloadableChips(cs),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _settings(cs),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Row(
      children: [
        Icon(Icons.translate, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Text('OCR Settings',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClose,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  Widget _languageChips(List<OcrLanguage> langs, ColorScheme cs) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final lang in langs)
          FilterChip(
            label: Text('${lang.nativeName} (${lang.code})',
                style: const TextStyle(fontSize: 11)),
            selected: ocrState.isActive(lang.code),
            onSelected: (_) => onToggleLanguage(lang.code),
            selectedColor: cs.primaryContainer,
            avatar: lang.rtl
                ? const Icon(Icons.format_textdirection_r_to_l, size: 14)
                : null,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _downloadableChips(ColorScheme cs) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final lang in ocrState.availableLanguages)
          ActionChip(
            label: Text('${lang.name} (${lang.code})',
                style: const TextStyle(fontSize: 11)),
            avatar: const Icon(Icons.download, size: 14),
            onPressed: () => onDownloadLanguage?.call(lang.code),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _settings(ColorScheme cs) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Auto-detect language', style: TextStyle(fontSize: 13)),
          subtitle: const Text('Let ML Kit detect the script automatically',
              style: TextStyle(fontSize: 11)),
          value: ocrState.autoDetect,
          onChanged: onAutoDetectChanged,
          dense: true,
        ),
        SwitchListTile(
          title: const Text('Enhance contrast', style: TextStyle(fontSize: 13)),
          subtitle: const Text('Boost contrast before OCR for faded documents',
              style: TextStyle(fontSize: 11)),
          value: ocrState.enhanceContrast,
          onChanged: onContrastChanged,
          dense: true,
        ),
        SwitchListTile(
          title: const Text('Auto-deskew', style: TextStyle(fontSize: 13)),
          subtitle: const Text('Straighten rotated pages before scanning',
              style: TextStyle(fontSize: 11)),
          value: ocrState.deskew,
          onChanged: onDeskewChanged,
          dense: true,
        ),
        ListTile(
          title: const Text('Engine', style: TextStyle(fontSize: 13)),
          trailing: SegmentedButton<OcrEngine>(
            segments: const [
              ButtonSegment(value: OcrEngine.mlKit, label: Text('ML Kit', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: OcrEngine.tesseract, label: Text('Tesseract', style: TextStyle(fontSize: 11))),
            ],
            selected: {ocrState.engine},
            onSelectionChanged: (s) => onEngineChanged(s.first),
          ),
          dense: true,
        ),
      ],
    );
  }
}
