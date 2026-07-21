import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// A positioned overlay for inline text editing directly on the canvas.
///
/// ### How it works
/// When the user taps a text annotation (or taps to create new text), this
/// widget appears at the annotation's screen position as a transparent
/// `TextField` overlay. The user edits text in-place — no modal dialog needed.
///
/// ### Lifecycle
/// 1. Parent provides the annotation, canvas size, and an `onDone` callback.
/// 2. This widget auto-focuses the TextField on mount.
/// 3. On focus-loss (tap elsewhere) or explicit submit, `onDone` fires with
///    the edited text. Parent commits it as a single undo command.
/// 4. If text is empty on done, parent may delete the annotation.
///
/// ### Position
/// The widget is positioned via a `Positioned` in the parent's Stack using
/// normalised pos × canvasSize (same coordinate system as the annotation).
class InlineTextEditor extends StatefulWidget {
  final TextAnnotation annotation;
  final Size canvasSize;
  final VoidCallback onDone;
  final ValueChanged<String> onTextChanged;

  const InlineTextEditor({
    super.key,
    required this.annotation,
    required this.canvasSize,
    required this.onDone,
    required this.onTextChanged,
  });

  @override
  State<InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<InlineTextEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.annotation.text);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    // Auto-focus after the first frame so the keyboard appears immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    widget.onTextChanged(_controller.text);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.annotation;
    final fontSize = t.size * widget.canvasSize.height;

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: null,
      style: TextStyle(
        color: t.color,
        fontSize: fontSize.clamp(8.0, 120.0),
        fontWeight: t.bold ? FontWeight.w800 : FontWeight.w500,
        fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
        decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
        decorationColor: t.color,
        fontFamily: t.fontFamily,
        height: t.lineHeight,
      ),
      textAlign: t.textAlign,
      textDirection: t.textDirection,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
      onChanged: widget.onTextChanged,
      onSubmitted: (_) => _commit(),
      cursorColor: t.color,
    );
  }
}
