import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/router.dart';
import 'core/config/app_settings.dart';
import 'core/theme/app_theme.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Never show the red crash screen to users. Log in debug, show a
    // friendly placeholder in release so the app keeps running.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (kDebugMode) debugPrint('Caught FlutterError: ${details.exception}');
    };
    ErrorWidget.builder = (details) => const _FriendlyErrorWidget();

    // Load persisted settings (e.g. AI server URL) before the app starts.
    await AppSettings.instance.load();

    runApp(const ProviderScope(child: AiPdfApp()));
  }, (error, stack) {
    // Swallow uncaught async errors so a single failure never kills the app.
    if (kDebugMode) debugPrint('Uncaught zone error: $error');
  });
}

class AiPdfApp extends ConsumerWidget {
  const AiPdfApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'AI PDF',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
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
