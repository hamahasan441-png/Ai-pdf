import 'package:flutter/material.dart';

/// OCR Language Selection screen — lets users choose which languages
/// the OCR engine should recognize in a document.
///
/// Multi-select: a document can contain multiple languages (e.g. Kurdish + Arabic + English).
/// Primary audience languages are listed first. Models are downloaded on first use.
class OcrLanguageScreen extends StatefulWidget {
  final Set<String> selectedLanguages;
  final ValueChanged<Set<String>> onConfirm;

  const OcrLanguageScreen({
    super.key,
    required this.selectedLanguages,
    required this.onConfirm,
  });

  @override
  State<OcrLanguageScreen> createState() => _OcrLanguageScreenState();
}

class _OcrLanguageScreenState extends State<OcrLanguageScreen> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedLanguages);
    if (_selected.isEmpty) _selected.add('en'); // default
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Languages'),
        actions: [
          TextButton(
            onPressed: () {
              widget.onConfirm(_selected);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Select the languages present in your document. '
              'Models are downloaded on first use (~5MB each).',
            ),
          ),
          const Divider(),
          ..._languages.map((lang) {
            return CheckboxListTile(
              value: _selected.contains(lang.code),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(lang.code);
                  } else if (_selected.length > 1) {
                    _selected.remove(lang.code);
                  }
                });
              },
              title: Text(lang.name),
              subtitle: Text(lang.nativeName),
              secondary: lang.isPrimary
                  ? const Icon(Icons.star, color: Colors.amber, size: 18)
                  : null,
            );
          }),
        ],
      ),
    );
  }
}

class _Language {
  final String code;
  final String name;
  final String nativeName;
  final bool isPrimary;
  const _Language(this.code, this.name, this.nativeName, {this.isPrimary = false});
}

const _languages = [
  _Language('ku', 'Kurdish (Sorani)', 'کوردی سۆرانی', isPrimary: true),
  _Language('ar', 'Arabic', 'العربية', isPrimary: true),
  _Language('fa', 'Persian', 'فارسی', isPrimary: true),
  _Language('en', 'English', 'English', isPrimary: true),
  _Language('he', 'Hebrew', 'עברית'),
  _Language('tr', 'Turkish', 'Türkçe'),
  _Language('de', 'German', 'Deutsch'),
  _Language('fr', 'French', 'Français'),
  _Language('es', 'Spanish', 'Español'),
  _Language('it', 'Italian', 'Italiano'),
  _Language('pt', 'Portuguese', 'Português'),
  _Language('ru', 'Russian', 'Русский'),
  _Language('zh', 'Chinese (Simplified)', '简体中文'),
  _Language('ja', 'Japanese', '日本語'),
  _Language('ko', 'Korean', '한국어'),
  _Language('hi', 'Hindi', 'हिन्दी'),
  _Language('ur', 'Urdu', 'اردو'),
];
