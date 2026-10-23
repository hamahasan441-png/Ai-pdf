import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/core/services/tool_handoff.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/security/data/pdf_encryptor.dart';
import 'package:ai_pdf/features/security/data/pdf_password_service.dart';
import 'package:ai_pdf/features/security/presentation/pdf_protect_screen.dart';

void main() {
  test('protectFile writes an encrypted copy and keeps the original', () async {
    final tmp = Directory.systemTemp.createTempSync('protect');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final src = File('${tmp.path}/form.pdf')..writeAsBytesSync(File('test/fixtures/pdf/forms.pdf').readAsBytesSync());
    final out = await const PdfPasswordService().protectFile(
      sourcePath: src.path,
      password: 'pw',
      access: const PdfAccess(print: false),
      outputDirectory: () async => tmp,
    );
    expect(out, contains('form_protected_'));
    expect(() => PdfObjectStore.parse(File(out).readAsBytesSync()), throwsA(isA<PdfSourceException>()));
    expect(PdfObjectStore.parse(src.readAsBytesSync()).pages, hasLength(2), reason: 'the original is untouched');
    expect(tmp.listSync().where((f) => f.path.endsWith('.partial')), isEmpty);
  });

  testWidgets('the button waits for a file and two matching passwords', (tester) async {
    ToolHandoff.instance.set('/somewhere/report.pdf');
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PdfProtectScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('report.pdf'), findsOneWidget, reason: 'a handed-over file is used');
    FilledButton button() => tester.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));
    expect(button().onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(0), 'secret');
    await tester.enterText(find.byType(TextField).at(1), 'secreT');
    await tester.pump();
    expect(find.text('The passwords do not match'), findsOneWidget);
    expect(button().onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });
}
