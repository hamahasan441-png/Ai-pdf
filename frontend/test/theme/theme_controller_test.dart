import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_pdf/core/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to system when nothing is stored', () async {
    await ThemeController.instance.load();
    expect(ThemeController.instance.mode.value, ThemeMode.system);
  });

  test('set() persists the choice and load() restores it', () async {
    await ThemeController.instance.set(ThemeMode.dark);

    // Simulate a fresh launch: reset the in-memory value then reload.
    ThemeController.instance.mode.value = ThemeMode.system;
    await ThemeController.instance.load();

    expect(ThemeController.instance.mode.value, ThemeMode.dark);
  });

  test('updates the notifier immediately for live rebuilds', () async {
    ThemeController.instance.mode.value = ThemeMode.system;
    await ThemeController.instance.set(ThemeMode.light);
    expect(ThemeController.instance.mode.value, ThemeMode.light);
  });
}
