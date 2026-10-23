import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/application/editor_compare_controller.dart';
import 'package:ai_pdf/features/editor/data/document_diff_service.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_compare_sheet.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('compare sheet lists removed and added lines with stats', (tester) async {
    const state = EditorCompareState(
      active: true,
      lineSegments: [
        DiffSegment(DiffKind.unchanged, 'Intro line'),
        DiffSegment(DiffKind.removed, 'Old contract value'),
        DiffSegment(DiffKind.added, 'New contract value'),
      ],
      stats: DiffStats(added: 1, removed: 1, unchanged: 1),
    );
    await tester.pumpWidget(_host(const EditorCompareSheet(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('Old contract value'), findsOneWidget);
    expect(find.text('New contract value'), findsOneWidget);
    expect(find.text('Intro line'), findsOneWidget);
    expect(find.text('Removed: 1'), findsOneWidget);
    expect(find.text('Added: 1'), findsOneWidget);
  });

  testWidgets('an empty diff says the documents are identical', (tester) async {
    const state = EditorCompareState(
      active: true,
      lineSegments: [],
      stats: DiffStats(added: 0, removed: 0, unchanged: 0),
    );
    await tester.pumpWidget(_host(const EditorCompareSheet(state: state)));
    await tester.pumpAndSettle();

    expect(find.textContaining('same text'), findsOneWidget);
  });

  EditorCompareState withUnchanged(int n) => EditorCompareState(
        active: true,
        lineSegments: [
          const DiffSegment(DiffKind.removed, 'old'),
          for (var i = 1; i <= n; i++) DiffSegment(DiffKind.unchanged, 'same $i'),
        ],
        stats: DiffStats(added: 0, removed: 1, unchanged: n),
      );

  testWidgets('a short unchanged run is shown once, whole', (tester) async {
    await tester.pumpWidget(_host(EditorCompareSheet(state: withUnchanged(3))));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 3; i++) {
      expect(find.text('same $i'), findsOneWidget, reason: 'line $i exactly once');
    }
    expect(find.textContaining('more unchanged'), findsNothing);
  });

  testWidgets('a long unchanged run keeps two lines each side around the note', (tester) async {
    await tester.pumpWidget(_host(EditorCompareSheet(state: withUnchanged(7))));
    await tester.pumpAndSettle();
    for (final i in [1, 2, 6, 7]) {
      expect(find.text('same $i'), findsOneWidget);
    }
    for (final i in [3, 4, 5]) {
      expect(find.text('same $i'), findsNothing);
    }
    expect(find.textContaining('3 more unchanged'), findsOneWidget);
  });

  testWidgets('documents with only unchanged lines are reported identical', (tester) async {
    const state = EditorCompareState(
      active: true,
      lineSegments: [DiffSegment(DiffKind.unchanged, 'same')],
      stats: DiffStats(added: 0, removed: 0, unchanged: 1),
    );
    await tester.pumpWidget(_host(const EditorCompareSheet(state: state)));
    await tester.pumpAndSettle();
    expect(find.textContaining('same text'), findsOneWidget);
  });
}
