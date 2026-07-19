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

  const EditorScreenBody({
    super.key,
    required this.bytes,
    required this.loading,
    required this.detecting,
    required this.detectingLabel,
    required this.onPick,
    required this.documentViewport,
    required this.toolbar,
  });

  @override
  Widget build(BuildContext context) {
    if (bytes == null) {
      return EditorEmptyState(loading: loading, onPick: onPick);
    }
    return Stack(
      children: [
        documentViewport,
        EditorLoadingOverlay(
          loading: loading,
          detecting: detecting,
          detectingLabel: detecting ? detectingLabel : null,
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: toolbar),
      ],
    );
  }
}
