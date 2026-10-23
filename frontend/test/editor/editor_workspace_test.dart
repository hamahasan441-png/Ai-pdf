import 'dart:typed_data';
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/core/config/kurdish_localizations.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_mode.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_document_viewport.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_mode_bar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_screen_body.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_toolbar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_top_bar.dart';

Widget app(Widget child, {Locale? locale, ThemeData? theme}) => MaterialApp(
      locale: locale,
      theme: theme,
      localizationsDelegates: const [...AppLocalizations.localizationsDelegates, ...kurdishFallbackDelegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

/// Records what the toolbar asks for.
class Calls {
  final tools = <EditTool>[];
  final modes = <EditorMode>[];
  final actions = <String>[];
}

EditorToolbar toolbar(
  Calls calls, {
  required EditorMode mode,
  EditTool tool = EditTool.pan,
  bool editingText = false,
  Widget? pageStrip,
}) {
  VoidCallback act(String name) => () => calls.actions.add(name);
  return EditorToolbar(
    mode: mode,
    onModeChanged: calls.modes.add,
    tool: tool,
    detecting: false,
    editingText: editingText,
    showFields: false,
    hasPageFields: false,
    isShape: false,
    color: Colors.red,
    stroke: 3,
    textSize: 0.0145,
    bold: false,
    onToolChanged: calls.tools.add,
    onAutoFill: act('autoFill'),
    onAiFill: act('aiFill'),
    onEditTextTool: act('editText'),
    onAddFormField: act('addField'),
    onToggleFields: act('toggleFields'),
    onAddSignature: act('signature'),
    onPlaceSignatureDate: act('date'),
    onInsertProfileField: act('profile'),
    onRotatePage: act('rotate'),
    onAddStamp: act('stamp'),
    onAddImage: act('image'),
    onSearch: act('search'),
    onRedact: act('redact'),
    onOutline: act('outline'),
    onPageOps: act('pageOps'),
    onColorChanged: (_) => calls.actions.add('color'),
    onStrokeChanged: (_) => calls.actions.add('stroke'),
    onTextSizeChanged: (_) => calls.actions.add('textSize'),
    onToggleBold: act('bold'),
    pageStrip: pageStrip,
  );
}

void main() {
  test('every tool belongs to the workspace whose bar shows it', () {
    expect(EditorMode.forTool(EditTool.pan), EditorMode.view);
    expect(EditorMode.forTool(EditTool.text), EditorMode.text);
    for (final t in [EditTool.check, EditTool.cross, EditTool.checkbox]) {
      expect(EditorMode.forTool(t), EditorMode.sign, reason: '$t');
    }
    for (final t in [
      EditTool.select,
      EditTool.highlight,
      EditTool.underline,
      EditTool.strikeout,
      EditTool.squiggly,
      EditTool.draw,
      EditTool.line,
      EditTool.arrow,
      EditTool.rect,
      EditTool.oval,
      EditTool.whiteout,
      EditTool.note,
      EditTool.eraser,
      EditTool.dot,
      EditTool.dash,
    ]) {
      expect(EditorMode.forTool(t), EditorMode.annotate, reason: '$t');
    }
  });

  group('mode bar', () {
    testWidgets('names the five workspaces and switches between them', (tester) async {
      final picked = <EditorMode>[];
      await tester.pumpWidget(app(EditorModeBar(mode: EditorMode.view, onChanged: picked.add)));
      for (final label in ['View', 'Annotate', 'Text', 'Fill & Sign', 'Pages']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Annotate'));
      await tester.tap(find.text('View'));
      expect(picked, [EditorMode.annotate], reason: 'tapping the open workspace does nothing');
      final view = tester.getSemantics(find.bySemanticsLabel('View'));
      expect(view.hasFlag(SemanticsFlag.isSelected), isTrue);
    });

    testWidgets('fits a narrow phone in Kurdish without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(EditorModeBar(mode: EditorMode.sign, onChanged: (_) {}), locale: const Locale('ku')));
      expect(tester.takeException(), isNull);
    });
  });

  group('tool row', () {
    testWidgets('reading shows no tool row, only the workspaces', (tester) async {
      final calls = Calls();
      await tester.pumpWidget(app(Align(alignment: Alignment.bottomCenter, child: toolbar(calls, mode: EditorMode.view))));
      expect(find.byTooltip('Highlight'), findsNothing);
      expect(find.byTooltip('Edit Text'), findsNothing);
      expect(tester.getSize(find.byType(EditorToolbar)).height, lessThan(EditorModeBar.height + 8));
    });

    testWidgets('annotate offers the markup tools and reports the pick', (tester) async {
      final calls = Calls();
      await tester.pumpWidget(app(Align(
        alignment: Alignment.bottomCenter,
        child: toolbar(calls, mode: EditorMode.annotate, tool: EditTool.select),
      )));
      for (final t in ['Select', 'Highlight', 'Draw', 'Note', 'Eraser']) {
        expect(find.byTooltip(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.byTooltip('Highlight'));
      expect(calls.tools, [EditTool.highlight]);
      expect(tester.getSemantics(find.bySemanticsLabel('Select')).hasFlag(SemanticsFlag.isSelected), isTrue);
      // The fill-and-sign tools live in their own workspace.
      expect(find.byTooltip('Sign'), findsNothing);
    });

    testWidgets('the style chip opens colour and thickness for drawing', (tester) async {
      final calls = Calls();
      await tester.pumpWidget(app(Align(
        alignment: Alignment.bottomCenter,
        child: toolbar(calls, mode: EditorMode.annotate, tool: EditTool.draw),
      )));
      await tester.tap(find.byTooltip('Colour and size'));
      await tester.pumpAndSettle();
      expect(find.text('Thickness'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      expect(calls.actions, contains('stroke'));
    });

    testWidgets('edit text toggles editing the page text and shows it on', (tester) async {
      final calls = Calls();
      await tester.pumpWidget(app(Align(
        alignment: Alignment.bottomCenter,
        child: toolbar(calls, mode: EditorMode.text, editingText: true),
      )));
      expect(tester.getSemantics(find.bySemanticsLabel('Edit Text')).hasFlag(SemanticsFlag.isSelected), isTrue);
      await tester.tap(find.byTooltip('Edit Text'));
      await tester.tap(find.byTooltip('Find'));
      expect(calls.actions, ['editText', 'search']);
    });

    testWidgets('fill & sign groups signing, marks and fields', (tester) async {
      final calls = Calls();
      await tester.pumpWidget(app(Align(alignment: Alignment.bottomCenter, child: toolbar(calls, mode: EditorMode.sign))));
      await tester.tap(find.byTooltip('Sign'));
      await tester.tap(find.byTooltip('Check'));
      expect(calls.actions, ['signature']);
      expect(calls.tools, [EditTool.check]);
    });

    testWidgets('pages shows the page strip and the page actions', (tester) async {
      final calls = Calls();
      const strip = SizedBox(key: Key('strip'), height: 60);
      await tester.pumpWidget(app(Align(
        alignment: Alignment.bottomCenter,
        child: toolbar(calls, mode: EditorMode.pages, pageStrip: strip),
      )));
      expect(find.byKey(const Key('strip')), findsOneWidget);
      await tester.tap(find.byTooltip('Rotate'));
      expect(calls.actions, ['rotate']);

      await tester.pumpWidget(app(Align(
        alignment: Alignment.bottomCenter,
        child: toolbar(calls, mode: EditorMode.annotate, pageStrip: strip),
      )));
      expect(find.byKey(const Key('strip')), findsNothing, reason: 'the strip belongs to Pages only');
    });
  });

  group('top bar', () {
    EditorTopBar bar(EditorMode mode, List<String> calls) => EditorTopBar(
          mode: mode,
          title: 'report.pdf',
          subtitle: 'Page 1 of 3',
          hasDocument: true,
          canUndo: false,
          canRedo: false,
          canPaste: false,
          loading: false,
          onExport: () => calls.add('export'),
          onSearch: () => calls.add('search'),
          onDone: () => calls.add('done'),
          menu: [EditorMenuAction(Icons.toc, 'Outline', () => calls.add('outline'))],
        );

    testWidgets('reading: search, share and a menu; no Done', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(app(bar(EditorMode.view, calls)));
      expect(find.text('Done'), findsNothing);
      await tester.tap(find.byTooltip('Find'));
      await tester.tap(find.byTooltip('Export'));
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();
      expect(calls, ['search', 'export', 'outline']);
    });

    testWidgets('a workspace: undo, redo and Done, nothing else', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(app(bar(EditorMode.annotate, calls)));
      expect(find.byTooltip('Export'), findsNothing);
      expect(find.byTooltip('More actions'), findsNothing);
      await tester.tap(find.text('Done'));
      expect(calls, ['done']);
    });

    test('text on the accent stays readable in both themes', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final b in Brightness.values) {
        final p = b == Brightness.dark ? EditorPalette.darkPalette : EditorPalette.lightPalette;
        expect(contrast(p.accent, p.onAccent), greaterThanOrEqualTo(4.5), reason: '$b');
      }
    });
  });

  group('full screen', () {
    Widget body({required bool hidden, bool pill = false}) => EditorScreenBody(
          bytes: Uint8List(1),
          loading: false,
          detecting: false,
          detectingLabel: null,
          onPick: () {},
          topBar: const SizedBox(key: Key('top'), height: 56),
          documentViewport: const ColoredBox(key: Key('page'), color: Colors.white),
          toolbar: const SizedBox(key: Key('bottom'), height: 120),
          chromeHidden: hidden,
          pageLabel: '2 / 9',
          showPageLabel: pill,
        );

    testWidgets('hiding the bars gives the page the whole screen and back', (tester) async {
      await tester.pumpWidget(app(body(hidden: false)));
      final withBars = tester.getSize(find.byKey(const Key('page'))).height;
      await tester.pumpWidget(app(body(hidden: true, pill: true)));
      await tester.pumpAndSettle();
      final full = tester.getSize(find.byKey(const Key('page'))).height;
      expect(full - withBars, closeTo(56 + 120, 0.5));
      expect(find.text('2 / 9'), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(find.ancestor(of: find.text('2 / 9'), matching: find.byType(AnimatedOpacity))).opacity, 1);
      // A folded bar takes no taps.
      expect(find.byKey(const Key('top')).hitTestable(), findsNothing);

      await tester.pumpWidget(app(body(hidden: false, pill: true)));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('page'))).height, closeTo(withBars, 0.5));
      expect(tester.widget<AnimatedOpacity>(find.ancestor(of: find.text('2 / 9'), matching: find.byType(AnimatedOpacity))).opacity, 0,
          reason: 'the page number shows only while the bars are hidden');
    });
  });

  group('viewport gestures', () {
    Future<(List<int>, List<String>, TransformationController)> pump(
      WidgetTester tester, {
      bool innerDrag = false,
    }) async {
      final swipes = <int>[];
      final taps = <String>[];
      final controller = TransformationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(Stack(children: [
        EditorDocumentViewport(
          panEnabled: true,
          scaleEnabled: true,
          transformationController: controller,
          onSwipePage: swipes.add,
          onBackgroundTap: () => taps.add('background'),
          child: GestureDetector(
            onTapUp: (_) => taps.add('page'),
            // The canvas takes drags only when its tool uses them.
            onPanStart: innerDrag ? (_) {} : null,
            child: const ColoredBox(key: Key('page'), color: Colors.white),
          ),
        ),
      ])));
      return (swipes, taps, controller);
    }

    testWidgets('a sideways fling turns the page either way', (tester) async {
      final (swipes, _, _) = await pump(tester);
      await tester.fling(find.byKey(const Key('page')), const Offset(-300, 0), 2000);
      await tester.pumpAndSettle();
      await tester.fling(find.byKey(const Key('page')), const Offset(300, 0), 2000);
      await tester.pumpAndSettle();
      expect(swipes, [1, -1]);
    });

    testWidgets('slow drags, vertical flings and a zoomed page do not turn it', (tester) async {
      final (swipes, _, controller) = await pump(tester);
      await tester.drag(find.byKey(const Key('page')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.fling(find.byKey(const Key('page')), const Offset(-60, -300), 2000);
      await tester.pumpAndSettle();
      controller.value = Matrix4.identity()..scale(2.0);
      await tester.fling(find.byKey(const Key('page')), const Offset(-300, 0), 2000);
      await tester.pumpAndSettle();
      expect(swipes, isEmpty);
    });

    testWidgets('while a tool uses drags, a fling stays with the page', (tester) async {
      final (swipes, _, _) = await pump(tester, innerDrag: true);
      await tester.fling(find.byKey(const Key('page')), const Offset(-300, 0), 2000);
      await tester.pumpAndSettle();
      expect(swipes, isEmpty);
    });

    testWidgets('a tap on the page is the page\'s; beside it, the background\'s', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (_, taps, _) = await pump(tester);
      final page = tester.getRect(find.byKey(const Key('page')));
      await tester.tapAt(page.center);
      await tester.pump(const Duration(milliseconds: 400));
      // The A4 page is narrower than the landscape screen: tap the margin.
      await tester.tapAt(Offset(page.left / 2, page.center.dy));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, ['page', 'background']);
    });
  });
}
