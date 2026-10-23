import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colours the user picked recently, newest first, kept across sessions.
class RecentColors {
  RecentColors._();

  static const int max = 8;
  static const String _key = 'editor_recent_colors';
  static List<Color> _cache = const [];

  /// The list as last loaded or pushed.
  static List<Color> get current => _cache;

  static Future<List<Color>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cache = [
        for (final v in prefs.getStringList(_key) ?? const <String>[])
          if (parseHex(v) case final c?) c,
      ];
    } catch (e) {
      // Recent colours are a convenience; without storage the list is empty.
      debugPrint('Recent colours not loaded: $e');
    }
    return _cache;
  }

  /// [color] first, without duplicates, at most [max].
  static List<Color> pushed(List<Color> list, Color color) =>
      [color, ...list.where((c) => c.toARGB32() != color.toARGB32())].take(max).toList();

  static Future<void> push(Color color) async {
    _cache = pushed(_cache, color);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, [for (final c in _cache) toHex(c)]);
    } catch (e) {
      debugPrint('Recent colours not saved: $e');
    }
  }
}

/// `#RRGGBB` for an opaque colour, `#AARRGGBB` otherwise.
String toHex(Color c) {
  final argb = c.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final a = argb >>> 24;
  return a == 0xFF ? '#$rgb' : '#${a.toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
}

/// Parses `#RGB`, `#RRGGBB` or `#AARRGGBB` (the `#` is optional). Null when
/// the text is not a colour.
Color? parseHex(String text) {
  var h = text.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) return null;
  if (h.length == 3) h = h.split('').map((d) => '$d$d').join();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  return Color(int.parse(h, radix: 16));
}

/// Palette: greys, then ten hues in four shades each.
final List<Color> editorPalette = [
  Colors.black,
  const Color(0xFF424242),
  const Color(0xFF757575),
  const Color(0xFFBDBDBD),
  Colors.white,
  for (final swatch in <MaterialColor>[
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.indigo,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.yellow,
    Colors.orange,
    Colors.brown,
  ])
    for (final shade in const [300, 500, 700, 900]) swatch[shade]!,
];

/// Full colour picker: recent colours, a palette and a hex field. Returns the
/// chosen colour (also added to the recent list), or null if dismissed.
Future<Color?> showEditorTextColorPickerSheet(
  BuildContext context, {
  required Color selectedColor,
  String? title,
}) async {
  if (RecentColors.current.isEmpty) await RecentColors.load();
  if (!context.mounted) return null;
  final picked = await showModalBottomSheet<Color>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ColorPicker(
      title: title ?? AppLocalizations.of(ctx)!.colorTitle,
      selected: selectedColor,
      recent: RecentColors.current,
    ),
  );
  if (picked != null) await RecentColors.push(picked);
  return picked;
}

class _ColorPicker extends StatefulWidget {
  final String title;
  final Color selected;
  final List<Color> recent;

  const _ColorPicker({required this.title, required this.selected, required this.recent});

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late final TextEditingController _hex = TextEditingController(text: toHex(widget.selected));
  String? _hexError;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _submitHex() {
    final c = parseHex(_hex.text);
    if (c == null) {
      setState(() => _hexError = AppLocalizations.of(context)!.colorHexError);
      return;
    }
    Navigator.pop(context, c);
  }

  Widget _swatch(Color c) {
    final selected = c.toARGB32() == widget.selected.toARGB32();
    return Semantics(
      button: true,
      selected: selected,
      label: AppLocalizations.of(context)!.cColorSwatchLabel(toHex(c)),
      child: InkResponse(
        onTap: () => Navigator.pop(context, c),
        radius: 22,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.black26,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: text.titleMedium),
              if (widget.recent.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(l10n.colorRecent, style: text.labelMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 10, runSpacing: 10, children: [for (final c in widget.recent) _swatch(c)]),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [for (final c in editorPalette) _swatch(c)]),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hex,
                      decoration: InputDecoration(
                        labelText: l10n.colorHex,
                        errorText: _hexError,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      autocorrect: false,
                      onChanged: (_) {
                        if (_hexError != null) setState(() => _hexError = null);
                      },
                      onSubmitted: (_) => _submitHex(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _submitHex, child: Text(l10n.colorUse)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
