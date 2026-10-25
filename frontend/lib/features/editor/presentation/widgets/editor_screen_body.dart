import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:ai_pdf/core/theme/motion.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_empty_state.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_loading_overlay.dart';

/// The editor's layout: the top bar, the page area and the bottom bars in a
/// column. When [chromeHidden] the bars fold away and the page takes the
/// whole screen; the page area is the same widget either way, so the page,
/// its zoom and anything being edited keep their state.
class EditorScreenBody extends StatelessWidget {
  final Uint8List? bytes;
  final bool loading;
  final bool detecting;
  final String? detectingLabel;
  final VoidCallback onPick;
  final Widget topBar;
  final Widget documentViewport;
  final Widget toolbar;

  /// Full-screen reading: the bars are folded away.
  final bool chromeHidden;

  /// "3 / 8": shown briefly over the page while the bars are hidden.
  final String? pageLabel;
  final bool showPageLabel;
  final Widget? inlineOverlay;
  final Widget? richTextToolbar;
  final Widget? searchBar;

  /// A bar naming the current task (such as placing a field) with a button
  /// to end it.
  final Widget? modeBanner;

  /// The bar on top of the keyboard while filling a form.
  final Widget? formFillBar;
  final Widget? textSelectionBar;
  final Widget? outlinePanel;
  final Widget? layerPanel;
  final Widget? pageOpsDialog;

  const EditorScreenBody({
    super.key,
    required this.bytes,
    required this.loading,
    required this.detecting,
    required this.detectingLabel,
    required this.onPick,
    required this.topBar,
    required this.documentViewport,
    required this.toolbar,
    this.chromeHidden = false,
    this.pageLabel,
    this.showPageLabel = false,
    this.inlineOverlay,
    this.richTextToolbar,
    this.searchBar,
    this.modeBanner,
    this.formFillBar,
    this.textSelectionBar,
    this.outlinePanel,
    this.layerPanel,
    this.pageOpsDialog,
  });

  @override
  Widget build(BuildContext context) {
    if (bytes == null) {
      return Column(
        children: [
          topBar,
          Expanded(child: EditorEmptyState(loading: loading, onPick: onPick)),
        ],
      );
    }
    final duration = Motion.of(context, Motion.medium);
    final page = Stack(
      fit: StackFit.expand,
      children: [
        documentViewport,
        if (inlineOverlay != null) inlineOverlay!,
        // The bars over the page slide in and out instead of popping.
        Positioned(
          left: 16,
          right: 16,
          top: 8,
          child: MotionReveal(
            child: searchBar == null && modeBanner == null
                ? null
                : KeyedSubtree(
                    key: ValueKey(searchBar != null ? 'search' : 'mode'),
                    child: searchBar ?? modeBanner!,
                  ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 12,
          child: MotionReveal(from: const Offset(0, 0.3), child: textSelectionBar),
        ),
        if (outlinePanel != null) Positioned(left: 0, top: 0, bottom: 0, child: outlinePanel!),
        if (layerPanel != null) Positioned(right: 0, top: 0, bottom: 0, child: layerPanel!),
      ],
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            _Fold(visible: !chromeHidden, duration: duration, alignment: Alignment.bottomCenter, child: topBar),
            Expanded(child: page),
            _Fold(visible: !chromeHidden, duration: duration, alignment: Alignment.topCenter, child: toolbar),
          ],
        ),
        EditorLoadingOverlay(
          loading: loading,
          detecting: detecting,
          detectingLabel: detecting ? detectingLabel : null,
        ),
        if (richTextToolbar != null) richTextToolbar!,
        // Rides on the keyboard (or the bottom edge when it is closed).
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.viewInsetsOf(context).bottom,
          child: MotionReveal(from: const Offset(0, 0.5), child: formFillBar),
        ),
        if (pageLabel != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: chromeHidden && showPageLabel ? 1 : 0,
                  duration: duration,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xE61B2130),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x33FFFFFF)),
                    ),
                    child: Text(
                      pageLabel!,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (pageOpsDialog != null) pageOpsDialog!,
      ],
    );
  }
}

/// Folds a bar to nothing and back, so the page area grows into its space.
class _Fold extends StatelessWidget {
  final bool visible;
  final Duration duration;
  final Alignment alignment;
  final Widget child;

  const _Fold({required this.visible, required this.duration, required this.alignment, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        alignment: alignment,
        heightFactor: visible ? 1 : 0,
        duration: duration,
        curve: Motion.enter,
        child: IgnorePointer(ignoring: !visible, child: child),
      ),
    );
  }
}
