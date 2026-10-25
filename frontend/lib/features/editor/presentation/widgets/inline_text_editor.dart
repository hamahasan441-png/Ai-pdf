import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/editor_text_runs.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/rtl_detection_service.dart';

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

  /// Keyboard for this box. A phone or email field should not get the
  /// plain text keyboard.
  final TextInputType keyboardType;

  /// One line, with a Done key. A form value is one line; a free text box
  /// is not, so it keeps the newline key.
  final bool singleLine;

  /// Shown while the box is empty. A detected field uses its own label,
  /// so the name of the field is still there after the old dialog went away.
  final String? hint;

  const InlineTextEditor({
    super.key,
    required this.annotation,
    required this.canvasSize,
    required this.onDone,
    required this.onTextChanged,
    this.onSelectionChanged,
    this.keyboardType = TextInputType.text,
    this.singleLine = false,
    this.hint,
  });

  @override
  State<InlineTextEditor> createState() => _InlineTextEditorState();
}

/// Shows the box's rich-text runs while editing, as long as they still spell
/// the field's text (the parent keeps them in step as the text changes).
class _RunsController extends TextEditingController {
  TextAnnotation annotation;

  _RunsController(this.annotation, {super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final runs = annotation.runs;
    final composing = withComposing && value.isComposingRangeValid;
    if (runs == null || runs.isEmpty || composing || runs.map((r) => r.text).join() != text) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final span = buildAnnotationTextSpan(annotation, style ?? const TextStyle());
    return TextSpan(style: style, children: span.children);
  }
}

class _InlineTextEditorState extends State<InlineTextEditor> {
  static const _rtl = RtlDetectionService();
  late final _RunsController _controller;
  late final FocusNode _focusNode;
  String? _boundId;

  @override
  void initState() {
    super.initState();
    _boundId = widget.annotation.id;
    _controller = _RunsController(widget.annotation, text: widget.annotation.text);
    _controller.addListener(_onSelectionUpdate);
    _focusNode = FocusNode();
    // Auto-focus after the first frame so the keyboard appears immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(InlineTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.annotation;
    _controller.annotation = next;
    final switched = next.id != _boundId;
    if (switched) {
      _boundId = next.id;
      _controller.value = TextEditingValue(
        text: next.text,
        selection: TextSelection.collapsed(offset: next.text.length),
      );
      return;
    }
    // Same box. Do not push annotation text back into the field while it is
    // focused — that resets the caret on every parent rebuild.
    if (!_focusNode.hasFocus && _controller.text != next.text) {
      _controller.value = TextEditingValue(
        text: next.text,
        selection: TextSelection.collapsed(offset: next.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionUpdate);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
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
    // The same style, direction and alignment the committed box uses, so the
    // text does not move or change when editing ends.
    final box = AnnotationTextLayout.of(t, widget.canvasSize);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: widget.singleLine ? 1 : null,
        textInputAction: widget.singleLine ? TextInputAction.done : TextInputAction.newline,
        style: box.style,
        textAlign: box.align,
        keyboardType: widget.keyboardType,
        textDirection: t.textDirection ??
            (_rtl.isRtl(_controller.text.isEmpty ? (widget.hint ?? '') : _controller.text)
                ? TextDirection.rtl
                : TextDirection.ltr),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: widget.hint,
          hintStyle: box.style.copyWith(color: const Color(0xFF8B93A7), fontWeight: FontWeight.w500),
        ),
        onChanged: widget.onTextChanged,
        onSubmitted: (_) => _commit(),
        // A white caret on a white page cannot be seen.
        cursorColor: t.color.computeLuminance() > 0.85 ? const Color(0xFF1F2430) : t.color,
      ),
    );
  }
}
