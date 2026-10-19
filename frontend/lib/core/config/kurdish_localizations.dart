import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Flutter ships no Material, Cupertino or Widgets localizations for Kurdish
/// (`ku`, nor `ckb`). Without them a Kurdish UI has no MaterialLocalizations,
/// so text fields, dialogs and menus fail, and nothing switches the layout to
/// right to left. These delegates give Sorani the Arabic ones: right to left,
/// Arabic script and Arabic-Indic digits, as Sorani is written. The app's own
/// strings stay Kurdish (AppLocalizations has `ku`).
class _KurdishFallback<T> extends LocalizationsDelegate<T> {
  final LocalizationsDelegate<T> inner;

  const _KurdishFallback(this.inner);

  static const fallback = Locale('ar');

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<T> load(Locale locale) => inner.load(fallback);

  @override
  bool shouldReload(_KurdishFallback<T> old) => false;
}

const kurdishFallbackDelegates = <LocalizationsDelegate<dynamic>>[
  _KurdishFallback<MaterialLocalizations>(GlobalMaterialLocalizations.delegate),
  _KurdishFallback<CupertinoLocalizations>(GlobalCupertinoLocalizations.delegate),
  _KurdishFallback<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
];

/// The app's supported locale for the device's [preferred] list. Android
/// reports Central Kurdish (Sorani) as `ckb`; the app's Kurdish is `ku`. A
/// device language the app does not have gets English (Flutter's default
/// would be the first supported locale, Arabic).
Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final p in preferred ?? const <Locale>[]) {
    final code = p.languageCode == 'ckb' ? 'ku' : p.languageCode;
    for (final s in supported) {
      if (s.languageCode == code) return s;
    }
  }
  for (final s in supported) {
    if (s.languageCode == 'en') return s;
  }
  return supported.first;
}
