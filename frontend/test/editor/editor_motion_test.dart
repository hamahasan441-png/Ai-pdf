import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/core/config/kurdish_localizations.dart';
import 'package:ai_pdf/core/theme/motion.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/edit_text_target.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_mode_banner.dart';

Widget app(Widget child, {Locale? locale, bool reduceMotion = false}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [...AppLocalizations.localizationsDelegates, ...kurdishFallbackDelegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  group('Kurdish', () {
    testWidgets('a Kurdish UI has Material localizations and runs right to left', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(app(
        Builder(builder: (context) {
          ctx = context;
          return const TextField();
        }),
        locale: const Locale('ku'),
      ));
      expect(tester.takeException(), isNull, reason: 'TextField needs MaterialLocalizations');
      expect(Directionality.of(ctx), TextDirection.rtl);
      expect(MaterialLocalizations.of(ctx), isNotNull);
      expect(AppLocalizations.of(ctx)!.localeName, 'ku');
    });

    test('a Central Kurdish phone (ckb) gets the Kurdish UI; unknown languages get English', () {
      const supported = AppLocalizations.supportedLocales;
      expect(resolveAppLocale(const [Locale('ckb', 'IQ')], supported), const Locale('ku'));
      expect(resolveAppLocale(const [Locale('fr'), Locale('ar')], supported), const Locale('ar'));
      expect(resolveAppLocale(const [Locale('fr')], supported), const Locale('en'));
      expect(resolveAppLocale(null, supported), const Locale('en'));
    });
  });

  group('motion', () {
    testWidgets('bars slide in, and appear at once when animations are off', (tester) async {
      Widget reveal(bool shown, {bool reduce = false}) =>
          app(MotionReveal(child: shown ? const Text('bar', key: ValueKey('bar')) : null), reduceMotion: reduce);

      await tester.pumpWidget(reveal(false));
      await tester.pumpWidget(reveal(true));
      await tester.pump(const Duration(milliseconds: 50));
      final mid = tester.widget<FadeTransition>(
        find.ancestor(of: find.text('bar'), matching: find.byType(FadeTransition)).first,
      );
      expect(mid.opacity.value, inExclusiveRange(0.0, 1.0), reason: 'still fading in');
      await tester.pumpAndSettle();

      await tester.pumpWidget(reveal(false, reduce: true));
      await tester.pumpWidget(reveal(true, reduce: true));
      await tester.pump();
      final now = tester.widget<FadeTransition>(
        find.ancestor(of: find.text('bar'), matching: find.byType(FadeTransition)).first,
      );
      expect(now.opacity.value, 1.0, reason: 'no animation with reduced motion');
    });

    testWidgets('the mode bar ends the mode; a paragraph target opens on tap', (tester) async {
      var done = 0, opened = 0;
      await tester.pumpWidget(app(Column(children: [
        EditorModeBanner(icon: Icons.edit_note, title: 'Edit text', hint: 'Tap a paragraph', doneLabel: 'Done', onDone: () => done++),
        SizedBox(width: 200, height: 40, child: EditTextTarget(label: 'Hello', onTap: () => opened++)),
      ])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.tap(find.bySemanticsLabel('Hello'));
      expect(done, 1);
      expect(opened, 1);
    });
  });
}
