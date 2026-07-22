import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// A positioned overlay for inline text editing directly on the canvas.
///
/// ### How it works
/// When the user taps a text annotation (or taps to create new text), this
/// widget appears at the annotation's screen position as a transparent
/// `TextField` overlay. The user edits text in-place — no modal dialog needed.
///
/// ### Rich text selection
/// Exposes [onSelectionChanged] so the parent can show a styling toolbar when
/// the user has a non-collapsed selection. The parent calls back to apply
/// bold/italic/underline/colour to the selected range via the rich-text service.
///
/// ### Lifecycle
/// 1. Parent provides the annotation, canvas size, and an `onDone` callback.
/// 2. This widget auto-focuses the TextField on mount.
/// 3. On focus-loss (tap elsewhere) or explicit submit, `onDone` fires with
///    the edited text. Parent commits it as a single undo command.
/// 4. If text is empty on done, parent may delete the annotation.
class InlineTextEditor extends StatefulWidget {
  final TextAnnotation annotation;
  final Size canvasSize;
  final VoidCallback onDone;
  final ValueChanged<String> onTextChanged;

  /// Fires when the user's text selection changes. The parent uses this to
  /// show/hide the rich-text formatting toolbar and apply per-range styling.
  final void Function(TextSelection selection)? onSelectionChanged;

  const InlineTextEditor({
    super.key,
    required this.annotation,
    required this.canvasSize,
    required this.onDone,
    required this.onTextChanged,
    this.onSelectionChanged,
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
    _controller.addListener(_onSelectionUpdate);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    // Auto-focus after the first frame so the keyboard appears immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionUpdate);
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

  void _onSelectionUpdate() {
    widget.onSelectionChanged?.call(_controller.selection);
  }

  void _commit() {
    widget.onTextChanged(_controller.text);
    widget.onDone();
  }

  /// The current selection — exposed so the parent can read it when applying
  /// a style toggle to the selected range.
  TextSelection get selection => _controller.selection;

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
        fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
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
