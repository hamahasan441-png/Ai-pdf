import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/presentation/widgets/editor_export_actions_sheet.dart';

void main() {
  Future<EditorExportActionResult?> pick(WidgetTester tester, String label) async {
    EditorExportActionResult? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showEditorExportActionsSheet(context, outPath: '/x/out.pdf'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('after export: print, protect and share are offered', (tester) async {
    expect((await pick(tester, 'Print'))?.kind, 'print');
    final protect = await pick(tester, 'Protect with password');
    expect(protect?.kind, 'route');
    expect(protect?.route, '/tools/protect');
    expect(protect?.handoffPath, '/x/out.pdf', reason: 'the protect screen opens the exported file');
    expect((await pick(tester, 'Share'))?.kind, 'share');
  });
}
