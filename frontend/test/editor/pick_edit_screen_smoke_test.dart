import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_pdf/core/config/kurdish_localizations.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_mode_bar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_top_bar.dart';
import 'package:ai_pdf/features/tools/presentation/pick_edit_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final locale in const [Locale('en'), Locale('ku')]) {
    testWidgets('the editor opens without a document in $locale', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: const [...AppLocalizations.localizationsDelegates, ...kurdishFallbackDelegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PickEditScreen(),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(EditorTopBar), findsOneWidget);
      // Nothing to edit yet: no workspaces, no share.
      expect(find.byType(EditorModeBar), findsNothing);
      expect(find.byIcon(Icons.ios_share), findsNothing);
    });
  }
}
