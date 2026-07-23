import 'package:flutter/material.dart';

/// Custom Stamp Creator — design your own text or image-based stamps
/// to reuse across documents. Saved locally for instant access.
class CustomStampCreatorScreen extends StatefulWidget {
  const CustomStampCreatorScreen({super.key});

  @override
  State<CustomStampCreatorScreen> createState() => _CustomStampCreatorScreenState();
}

class _CustomStampCreatorScreenState extends State<CustomStampCreatorScreen> {
  final _textController = TextEditingController(text: 'APPROVED');
  Color _borderColor = Colors.green;
  Color _textColor = Colors.green;
  double _borderWidth = 3.0;
  double _fontSize = 24.0;
  bool _rounded = true;
  bool _filled = false;

  static const _colorOptions = [
    Colors.green, Colors.red, Colors.blue, Colors.orange,
    Colors.purple, Colors.brown, Colors.black, Colors.teal,
  ];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Stamp'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Live preview
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: _borderColor, width: _borderWidth),
                borderRadius: _rounded ? BorderRadius.circular(8) : null,
                color: _filled ? _borderColor.withOpacity(0.1) : null,
              ),
              child: Text(
                _textController.text.isEmpty ? 'STAMP' : _textController.text,
                style: TextStyle(
                  fontSize: _fontSize,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Text input
          TextField(
            controller: _textController,
            decoration: const InputDecoration(labelText: 'Stamp text', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Color palette
          Text('Color', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _colorOptions.map((c) {
              final selected = c == _borderColor;
              return GestureDetector(
                onTap: () => setState(() { _borderColor = c; _textColor = c; }),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: selected ? Border.all(color: theme.colorScheme.outline, width: 3) : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Options
          Row(
            children: [
              const Text('Font size: '),
              Expanded(
                child: Slider(
                  value: _fontSize, min: 12, max: 48, divisions: 18,
                  label: '${_fontSize.round()}',
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Border: '),
              Expanded(
                child: Slider(
                  value: _borderWidth, min: 1, max: 6, divisions: 5,
                  label: '${_borderWidth.round()}',
                  onChanged: (v) => setState(() => _borderWidth = v),
                ),
              ),
            ],
          ),
          SwitchListTile(
            title: const Text('Rounded corners'),
            value: _rounded,
            onChanged: (v) => setState(() => _rounded = v),
          ),
          SwitchListTile(
            title: const Text('Filled background'),
            value: _filled,
            onChanged: (v) => setState(() => _filled = v),
          ),
        ],
      ),
    );
  }

  void _save() {
    Navigator.pop(context, {
      'text': _textController.text,
      'color': _borderColor.value,
      'fontSize': _fontSize,
      'borderWidth': _borderWidth,
      'rounded': _rounded,
      'filled': _filled,
    });
  }
}
