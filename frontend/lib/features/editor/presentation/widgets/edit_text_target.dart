import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_pdf/core/theme/motion.dart';

/// A paragraph or line that "Edit text" offers: a soft tinted box that fades
/// in, darkens while pressed, and opens the text for editing on tap.
class EditTextTarget extends StatefulWidget {
  final VoidCallback onTap;
  final String label;

  const EditTextTarget({super.key, required this.onTap, required this.label});

  @override
  State<EditTextTarget> createState() => _EditTextTargetState();
}

class _EditTextTargetState extends State<EditTextTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.of(context, Motion.medium),
          curve: Motion.enter,
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.quick),
            curve: Motion.enter,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: _pressed ? 0.22 : 0.08),
              border: Border.all(color: cs.primary.withValues(alpha: _pressed ? 0.9 : 0.55), width: _pressed ? 1.6 : 1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
