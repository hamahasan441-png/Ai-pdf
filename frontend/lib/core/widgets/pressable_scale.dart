import 'package:flutter/material.dart';

/// A subtle, premium press micro-interaction.
///
/// Wraps any tappable content and gently scales it down while pressed, then
/// springs back on release. This tactile feedback makes the UI feel responsive
/// and polished without being distracting — a small cue that reinforces the
/// calm, considered feel of the app.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 120),
    this.borderRadius,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Scale applied while pressed (1.0 = no scale). Kept close to 1 for subtlety.
  final double pressedScale;
  final Duration duration;

  /// Optional radius so the tap ripple/overlay is clipped to the content shape.
  final BorderRadius? borderRadius;

  /// Light haptic tick on tap for a tactile, premium feel.
  final bool haptic;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) {
                // Soft, low-intensity feedback; safe no-op if unsupported.
                Feedback.forTap(context);
              }
              widget.onTap!.call();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.borderRadius != null
            ? ClipRRect(borderRadius: widget.borderRadius!, child: widget.child)
            : widget.child,
      ),
    );
  }
}
