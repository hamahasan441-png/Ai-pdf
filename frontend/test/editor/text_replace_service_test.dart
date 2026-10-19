import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/application/editor_search_controller.dart';
import 'package:ai_pdf/features/editor/data/document_search_service.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/data/text_replace_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/history/editor_command.dart';
import 'package:ai_pdf/features/editor/domain/history/editor_history.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_search_bar.dart';

PdfTextElement w(String text, double left, {double top = 0.1, Color? color}) =>
    PdfTextElement(text: text, rect: Rect.fromLTWH(left, top, 0.1, 0.02), fontSize: 12, color: color);

void main() {
  const search = DocumentSearchService();
  const replace = TextReplaceService();

  final pages = {
    0: [w('Invoice', 0.1), w('banana', 0.3, color: const Color(0xFF336699))],
    2: [w('INVOICE:', 0.1, top: 0.5)],
  };

  test('each matched word becomes an erasing whiteout and a new text box', () {
    final plan = replace.plan(pages, search.search(pages, 'invoice'), 'Bill', pageHeightPt: const {0: 800, 2: 800});
    expect(plan.replaced, 2);
    expect(plan.items.keys, [0, 2]);
    final whiteout = plan.items[0]![0] as ShapeAnnotation;
    expect(whiteout.type, ShapeType.whiteout);
    expect(whiteout.metadata[eraseTextKey], isTrue);
    expect(Rect.fromPoints(whiteout.start, whiteout.end), pages[0]![0].rect);
    expect((plan.items[0]![1] as TextAnnotation).text, 'Bill');
    // Only the matched part of a word changes; the rest of it stays.
    expect((plan.items[2]![1] as TextAnnotation).text, 'Bill:');
  });

  test('several matches in one word are one edit with the colour kept', () {
    final plan = replace.plan(pages, search.search(pages, 'an'), 'AN');
    expect(plan.replaced, 2);
    expect(plan.items[0], hasLength(2));
    final box = plan.items[0]![1] as TextAnnotation;
    expect(box.text, 'bANANa');
    expect(box.color, const Color(0xFF336699));
  });

  test('an empty replacement deletes the text: whiteout only', () {
    final plan = replace.plan(pages, search.search(pages, 'banana'), '');
    expect(plan.replaced, 1);
    expect(plan.items[0], hasLength(1));
    expect(plan.items[0]!.single, isA<ShapeAnnotation>());
  });

  test('a match that no longer reads the same is skipped, not guessed', () {
    final stale = search.search(pages, 'banana');
    final changed = {0: [w('Invoice', 0.1), w('cherry', 0.3)]};
    final plan = replace.plan(changed, stale, 'x');
    expect(plan.replaced, 0);
    expect(plan.items, isEmpty);
  });

  test('replaced words drop out of the searchable layer until undone', () {
    final layer = PageLayer();
    final history = EditorHistory();
    final plan = replace.plan(pages, search.search(pages, 'banana'), 'kiwi');
    history.push(AddBatchCommand(plan.items[0]!), layer);
    expect(search.search(replace.unreplaced(pages, {0: layer}), 'banana'), isEmpty);
    expect(search.search(replace.unreplaced(pages, {0: layer}), 'invoice'), hasLength(2));

    history.undo(layer);
    expect(layer.items, isEmpty, reason: 'one undo removes the whole replace');
    expect(search.search(replace.unreplaced(pages, {0: layer}), 'banana'), hasLength(1));
  });

  test('after the layer changes the search stays on the same match number', () {
    final c = EditorSearchController();
    c.setPages(pages);
    c.open();
    c.setQuery('invoice');
    expect(c.state.currentMatchIndex, 0);
    c.setPages({
      0: [w('banana', 0.3)],
      2: pages[2]!,
    });
    expect(c.state.matchCount, 1);
    expect(c.state.currentMatch!.pageIndex, 2, reason: 'the next match, not a restart');
  });

  testWidgets('the search bar replaces the current match or all of them', (tester) async {
    final replaced = <String>[];
    final c = EditorSearchController()..setPages(pages);
    c.open();
    c.setQuery('invoice');
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EditorSearchBar(
          searchState: c.state,
          onQueryChanged: (_) {},
          onNext: () {},
          onPrevious: () {},
          onClose: () {},
          onCaseSensitiveChanged: (_) {},
          onWholeWordChanged: (_) {},
          onReplace: (t) => replaced.add('one:$t'),
          onReplaceAll: (t) => replaced.add('all:$t'),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('replaceField')), findsNothing);
    await tester.tap(find.byTooltip('Find and replace'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('replaceField')), 'Bill');
    await tester.tap(find.text('Replace'));
    await tester.tap(find.text('Replace all'));
    expect(replaced, ['one:Bill', 'all:Bill']);
  });
}
