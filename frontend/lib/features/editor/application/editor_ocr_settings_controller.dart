import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A language available for OCR (Phase 45).
class OcrLanguage {
  final String code;
  final String name;
  final String nativeName;
  final bool downloaded;
  final bool rtl;

  const OcrLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    this.downloaded = false,
    this.rtl = false,
  });

  OcrLanguage copyWith({bool? downloaded}) => OcrLanguage(
        code: code,
        name: name,
        nativeName: nativeName,
        downloaded: downloaded ?? this.downloaded,
        rtl: rtl,
      );
}

/// UI state for the OCR language/settings panel (Phase 45).
class EditorOcrSettingsState {
  final bool visible;
  final List<OcrLanguage> languages;
  final List<String> activeLanguages;
  final bool autoDetect;
  final OcrEngine engine;
  final bool enhanceContrast;
  final bool deskew;

  const EditorOcrSettingsState({
    this.visible = false,
    this.languages = const [],
    this.activeLanguages = const ['en'],
    this.autoDetect = true,
    this.engine = OcrEngine.mlKit,
    this.enhanceContrast = true,
    this.deskew = true,
  });

  List<OcrLanguage> get downloadedLanguages =>
      languages.where((l) => l.downloaded).toList();

  List<OcrLanguage> get availableLanguages =>
      languages.where((l) => !l.downloaded).toList();

  bool isActive(String code) => activeLanguages.contains(code);

  EditorOcrSettingsState copyWith({
    bool? visible,
    List<OcrLanguage>? languages,
    List<String>? activeLanguages,
    bool? autoDetect,
    OcrEngine? engine,
    bool? enhanceContrast,
    bool? deskew,
  }) =>
      EditorOcrSettingsState(
        visible: visible ?? this.visible,
        languages: languages ?? this.languages,
        activeLanguages: activeLanguages ?? this.activeLanguages,
        autoDetect: autoDetect ?? this.autoDetect,
        engine: engine ?? this.engine,
        enhanceContrast: enhanceContrast ?? this.enhanceContrast,
        deskew: deskew ?? this.deskew,
      );
}

enum OcrEngine { mlKit, tesseract }

/// Controller for OCR language + settings (Phase 45).
///
/// Manages which OCR languages are active (multi-select for documents mixing
/// scripts), which engine to use, and preprocessing options (contrast boost,
/// deskew). Language packs can be downloaded on-demand. The field detection
/// and text scan services read the active languages from this controller.
final editorOcrSettingsProvider =
    StateNotifierProvider<EditorOcrSettingsController, EditorOcrSettingsState>(
        (ref) => EditorOcrSettingsController());

class EditorOcrSettingsController
    extends StateNotifier<EditorOcrSettingsState> {
  EditorOcrSettingsController() : super(const EditorOcrSettingsState()) {
    _initLanguages();
  }

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  void toggleLanguage(String code) {
    final active = [...state.activeLanguages];
    if (active.contains(code)) {
      if (active.length > 1) active.remove(code); // keep at least one
    } else {
      active.add(code);
    }
    state = state.copyWith(activeLanguages: active);
  }

  void setAutoDetect(bool value) => state = state.copyWith(autoDetect: value);
  void setEngine(OcrEngine engine) => state = state.copyWith(engine: engine);
  void setEnhanceContrast(bool value) =>
      state = state.copyWith(enhanceContrast: value);
  void setDeskew(bool value) => state = state.copyWith(deskew: value);

  /// Mark a language as downloaded (after the user downloads the pack).
  void markDownloaded(String code) {
    state = state.copyWith(
      languages: [
        for (final l in state.languages)
          if (l.code == code) l.copyWith(downloaded: true) else l,
      ],
    );
  }

  void _initLanguages() {
    const langs = [
      OcrLanguage(code: 'en', name: 'English', nativeName: 'English', downloaded: true),
      OcrLanguage(code: 'de', name: 'German', nativeName: 'Deutsch', downloaded: true),
      OcrLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية', downloaded: true, rtl: true),
      OcrLanguage(code: 'ku', name: 'Kurdish', nativeName: 'کوردی', downloaded: true, rtl: true),
      OcrLanguage(code: 'fa', name: 'Persian', nativeName: 'فارسی', rtl: true),
      OcrLanguage(code: 'tr', name: 'Turkish', nativeName: 'Türkçe'),
      OcrLanguage(code: 'fr', name: 'French', nativeName: 'Français'),
      OcrLanguage(code: 'es', name: 'Spanish', nativeName: 'Español'),
      OcrLanguage(code: 'it', name: 'Italian', nativeName: 'Italiano'),
      OcrLanguage(code: 'nl', name: 'Dutch', nativeName: 'Nederlands'),
      OcrLanguage(code: 'pt', name: 'Portuguese', nativeName: 'Português'),
      OcrLanguage(code: 'ru', name: 'Russian', nativeName: 'Русский'),
      OcrLanguage(code: 'zh', name: 'Chinese', nativeName: '中文'),
      OcrLanguage(code: 'ja', name: 'Japanese', nativeName: '日本語'),
      OcrLanguage(code: 'ko', name: 'Korean', nativeName: '한국어'),
      OcrLanguage(code: 'he', name: 'Hebrew', nativeName: 'עברית', rtl: true),
    ];
    state = state.copyWith(languages: langs);
  }
}
