import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/presentation/widgets/editor_empty_state.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_loading_overlay.dart';

class EditorScreenBody extends StatelessWidget {
  final Uint8List? bytes;
  final bool loading;
  final bool detecting;
  final String? detectingLabel;
  final VoidCallback onPick;
  final Widget documentViewport;
  final Widget toolbar;
  final Widget? inlineOverlay;
  final Widget? richTextToolbar;
  final Widget? thumbnailStrip;
  final Widget? searchBar;
  final Widget? redactionOverlay;
  final Widget? outlinePanel;
  final Widget? chatPanel;
  final Widget? layerPanel;
  final Widget? formReviewPanel;
  final Widget? pageOpsDialog;

  const EditorScreenBody({
    super.key,
    required this.bytes,
    required this.loading,
    required this.detecting,
    required this.detectingLabel,
    required this.onPick,
    required this.documentViewport,
    required this.toolbar,
    this.inlineOverlay,
    this.richTextToolbar,
    this.thumbnailStrip,
    this.searchBar,
    this.redactionOverlay,
    this.outlinePanel,
    this.chatPanel,
    this.layerPanel,
    this.formReviewPanel,
    this.pageOpsDialog,
  });

  @override
  Widget build(BuildContext context) {
    if (bytes == null) {
      return EditorEmptyState(loading: loading, onPick: onPick);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        documentViewport,
        if (redactionOverlay != null) redactionOverlay!,
        if (inlineOverlay != null) inlineOverlay!,
        EditorLoadingOverlay(
          loading: loading,
          detecting: detecting,
          detectingLabel: detecting ? detectingLabel : null,
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: toolbar),
        if (thumbnailStrip != null)
          Positioned(left: 0, right: 0, bottom: 96, child: thumbnailStrip!),
        if (richTextToolbar != null) richTextToolbar!,
        if (searchBar != null)
          Positioned(left: 16, right: 16, top: 8, child: searchBar!),
        if (outlinePanel != null)
          Positioned(left: 0, top: 0, bottom: 0, child: outlinePanel!),
        if (layerPanel != null)
          Positioned(right: 0, top: 0, bottom: 0, child: layerPanel!),
        if (chatPanel != null)
          Positioned(right: 0, top: 0, bottom: 0, child: chatPanel!),
        if (formReviewPanel != null)
          Positioned(left: 0, right: 0, bottom: 96, child: formReviewPanel!),
        if (pageOpsDialog != null) pageOpsDialog!,
      ],
    );
  }
}
