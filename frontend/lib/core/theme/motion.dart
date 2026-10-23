import 'package:flutter/material.dart';

/// Motion for the editor: short, eased, never bouncing or looping, so it
/// guides the eye without slowing anyone down. Everything is instant when
/// the system asks for reduced motion.
class Motion {
  Motion._();

  /// Small state changes: a toggle lighting up, a badge count.
  static const Duration quick = Duration(milliseconds: 120);

  /// Things appearing: a bar sliding in, a row expanding.
  static const Duration medium = Duration(milliseconds: 200);

  /// Larger surfaces: a sheet or panel.
  static const Duration slow = Duration(milliseconds: 280);

  /// Entering: fast start, gentle stop.
  static const Curve enter = Curves.easeOutCubic;

  /// Leaving: quick, out of the way.
  static const Curve exit = Curves.easeInCubic;

  /// [d], or zero when animations are turned off (accessibility setting).
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}

/// Shows [child] with a short fade and slide from [from] (a fraction of its
/// size), and hides it the same way when it becomes null. Used for the bars
/// that come and go over the page.
class MotionReveal extends StatelessWidget {
  final Widget? child;
  final Offset from;

  const MotionReveal({super.key, required this.child, this.from = const Offset(0, -0.25)});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      reverseDuration: Motion.of(context, Motion.quick),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: from, end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: child ?? const SizedBox.shrink(key: ValueKey('motion-reveal-empty')),
    );
  }
}
