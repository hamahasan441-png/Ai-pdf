import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show LicenseEntry, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/ads/ads_service.dart';
import 'core/config/router.dart';
import 'core/config/app_settings.dart';
import 'core/config/kurdish_localizations.dart';
import 'core/config/locale_controller.dart';
import 'core/observability/crash_reporter.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/subscription/application/subscription_controller.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Never show the red crash screen to users. Report every framework error
    // (to the console today; to Crashlytics/Sentry once a backend is wired via
    // Crash.setReporter) and show a friendly placeholder so the app keeps running.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      Crash.recordError(details.exception, details.stack,
          reason: details.context?.toString(), fatal: true);
    };
    ErrorWidget.builder = (details) => const _FriendlyErrorWidget();

    // SIL OFL 1.1 requires the licence to travel with the bundled fonts.
    LicenseRegistry.addLicense(_bundledFontLicenses);

    // Load persisted settings (AI server URL, theme, language) before start.
    await AppSettings.instance.load();
    await ThemeController.instance.load();
    await LocaleController.instance.load();

    // Ads init is fire-and-forget (free tier only; removed for Pro).
    AdsService.instance.init();

    runApp(const ProviderScope(child: AiPdfApp()));
  }, (error, stack) {
    // Report uncaught async errors instead of silently dropping them. The app
    // still keeps running (a single failure never kills it), but we are no
    // longer blind to it in production.
    Crash.recordError(error, stack, reason: 'uncaught zone error', fatal: true);
  });
}

class AiPdfApp extends ConsumerWidget {
  const AiPdfApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Keep the billing controller alive for the whole app lifetime so
    // subscription renewals / restores are always processed.
    ref.watch(subscriptionControllerProvider);
    // Free tier sees ads; Pro removes them everywhere.
    AdsService.instance.setPro(ref.watch(isProProvider));
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, themeMode, _) => ValueListenableBuilder<Locale?>(
        valueListenable: LocaleController.instance.locale,
        builder: (context, locale, __) => MaterialApp.router(
          title: 'Pdoczy',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          locale: locale,
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            ...kurdishFallbackDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          localeListResolutionCallback: resolveAppLocale,
          routerConfig: router,
        ),
      ),
    );
  }
}

/// Shown instead of the red error screen if a widget fails to build.
class _FriendlyErrorWidget extends StatelessWidget {
  const _FriendlyErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFFF8FAFC),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 48, color: Color(0xFF64748B)),
              SizedBox(height: 12),
              Text(
                'Something went wrong here.\nPlease go back and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF475569), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _fontLicenseFiles = {
  'Noto Sans': 'assets/fonts/licenses/OFL-NotoSans.txt',
  'Noto Sans Arabic': 'assets/fonts/licenses/OFL-NotoSansArabic.txt',
  'Noto Sans Hebrew': 'assets/fonts/licenses/OFL-NotoSansHebrew.txt',
  'Vazirmatn': 'assets/fonts/licenses/OFL-Vazirmatn.txt',
};

Stream<LicenseEntry> _bundledFontLicenses() async* {
  for (final entry in _fontLicenseFiles.entries) {
    try {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks([entry.key], text);
    } catch (_) {
      // A build without the licence file still starts.
    }
  }
}
