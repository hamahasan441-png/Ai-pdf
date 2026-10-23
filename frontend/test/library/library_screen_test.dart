import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_pdf/features/library/application/library_controller.dart';
import 'package:ai_pdf/features/library/data/library_repository.dart';
import 'package:ai_pdf/features/library/domain/entities/library_item.dart';
import 'package:ai_pdf/features/library/presentation/library_screen.dart';

/// Let real file work started from the widget tree finish: each await on
/// disk resumes in the test zone, so alternate real time with pumps.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory docs;
  late Directory picked;
  late LibraryController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    docs = Directory.systemTemp.createTempSync('library_docs');
    picked = Directory.systemTemp.createTempSync('library_picked');
    controller = LibraryController(repository: LibraryRepository(documentsDir: () async => docs));
  });

  tearDown(() {
    docs.deleteSync(recursive: true);
    picked.deleteSync(recursive: true);
  });

  File source(String name, int bytes) => File('${picked.path}/$name')..writeAsBytesSync(List.filled(bytes, 1));

  Future<void> pumpLibrary(WidgetTester tester, {List<File> pick = const []}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [libraryControllerProvider.overrideWith((_) => controller)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LibraryScreen(
          pickFiles: () async => [for (final f in pick) (path: f.path, name: f.uri.pathSegments.last)],
          countPages: (_) async => 3,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  test('importing copies the file into the library and lists it', () async {
    final pdf = source('report.pdf', 2048);
    final item = await controller.importFile(pdf.path, 'report.pdf', pageCount: 4);
    expect(item.type, LibraryItemType.pdf);
    expect(item.sizeBytes, 2048);
    expect(item.path, startsWith('${docs.path}/library/'));
    expect(File(item.path).existsSync(), isTrue);
    expect(pdf.existsSync(), isTrue, reason: 'the original stays where it was');

    // A second controller reads the same catalogue back.
    final again = LibraryController(repository: LibraryRepository(documentsDir: () async => docs));
    await again.load();
    expect(again.current.items.single.name, 'report.pdf');
    expect(LibraryController.typeOf('scan.JPG'), LibraryItemType.image);
  });

  test('a damaged catalogue keeps its good entries and a backup', () async {
    final good = LibraryItem(
      id: 'a',
      name: 'kept.pdf',
      path: '/x/kept.pdf',
      type: LibraryItemType.pdf,
      sizeBytes: 1,
      createdAt: DateTime(2026),
      modifiedAt: DateTime(2026),
    ).toJson();
    final raw = jsonEncode([good, 42, {'name': 'no id'}]);
    SharedPreferences.setMockInitialValues({'library_items_v1': raw});
    final items = await const LibraryRepository().loadItems();
    expect(items.map((i) => i.name), ['kept.pdf']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_items_v1.damaged'), raw);

    SharedPreferences.setMockInitialValues({'library_items_v1': '{not json'});
    expect(await const LibraryRepository().loadItems(), isEmpty);
    expect((await SharedPreferences.getInstance()).getString('library_items_v1.damaged'), '{not json');
  });

  testWidgets('import, rename, pin and delete from the item menu', (tester) async {
    late List<File> files;
    await tester.runAsync(() async => files = [source('contract.pdf', 10), source('photo.png', 5)]);
    await pumpLibrary(tester, pick: files);
    expect(find.text('No documents yet'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Import documents'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('contract.pdf'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('3 pages'), findsOneWidget, reason: 'the PDF is counted, the image is not');
    expect(find.text('Added 2 to the library'), findsOneWidget);

    Future<void> menu(String item, String action) async {
      await tester.tap(find.descendant(
        of: find.ancestor(of: find.text(item), matching: find.byType(InkWell)).first,
        matching: find.byTooltip('More options'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action).last);
      await tester.pumpAndSettle();
    }

    await menu('photo.png', 'Rename');
    await tester.enterText(find.byKey(const ValueKey('libraryName')), '  Holiday  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Holiday'), findsOneWidget);

    await menu('Holiday', 'Pin to top');
    expect(controller.current.items.firstWhere((i) => i.name == 'Holiday').isPinned, isTrue);

    await menu('contract.pdf', 'Delete');
    expect(find.text('Delete “contract.pdf”?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('contract.pdf'), findsOneWidget, reason: 'cancel keeps it');

    final path = controller.current.items.firstWhere((i) => i.name == 'contract.pdf').path;
    await menu('contract.pdf', 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await settleIo(tester);
    expect(find.text('contract.pdf'), findsNothing);
    expect(File(path).existsSync(), isFalse);
  });

  testWidgets('folders: filter, and deleting one keeps its documents', (tester) async {
    await tester.runAsync(() async {
      final item = await controller.importFile(source('a.pdf', 1).path, 'a.pdf');
      final folder = await controller.createFolder('Work');
      await controller.moveToFolder(item.id, folder.id);
      await controller.importFile(source('b.pdf', 1).path, 'b.pdf');
    });
    await pumpLibrary(tester);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('b.pdf'), findsNothing);

    await tester.longPress(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete folder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('are kept'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(controller.current.folders, isEmpty);
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('b.pdf'), findsOneWidget, reason: 'the filter on the deleted folder is dropped');
  });

  testWidgets('a search with no result offers to clear the filters', (tester) async {
    await tester.runAsync(() => controller.importFile(source('a.pdf', 1).path, 'a.pdf'));
    await pumpLibrary(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No documents match'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('a.pdf'), findsOneWidget);
  });

  testWidgets('a document whose file is gone says so and offers to remove it', (tester) async {
    late String path;
    await tester.runAsync(() async {
      path = (await controller.importFile(source('gone.pdf', 1).path, 'gone.pdf')).path;
      File(path).deleteSync();
    });
    await pumpLibrary(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('gone.pdf'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('This file is no longer on the device.'), findsOneWidget);
    await tester.tap(find.text('Remove from library'));
    await tester.pumpAndSettle();
    await settleIo(tester);
    expect(controller.current.items, isEmpty);
  });
}
