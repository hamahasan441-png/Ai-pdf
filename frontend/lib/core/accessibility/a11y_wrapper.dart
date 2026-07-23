import 'package:flutter/material.dart';

/// Accessibility helpers and semantic wrappers for the app.
///
/// Ensures TalkBack (Android) and VoiceOver (iOS) users can navigate and
/// use every feature. Key principles:
/// 1. Every interactive element has a semantic label
/// 2. Images have descriptions
/// 3. Custom widgets use [Semantics] to describe their purpose
/// 4. Page content is announced on navigation
///
/// Usage: wrap complex custom widgets with these helpers.
class A11y {
  A11y._();

  /// Wraps a widget with a semantic label for screen readers.
  static Widget label(Widget child, String description) {
    return Semantics(
      label: description,
      child: child,
    );
  }

  /// Marks a widget as a button with a label.
  static Widget button(Widget child, String label, {VoidCallback? onTap}) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: child,
    );
  }

  /// Marks an image with a description.
  static Widget image(Widget child, String description) {
    return Semantics(
      image: true,
      label: description,
      child: child,
    );
  }

  /// Marks a header for navigation landmarks.
  static Widget header(Widget child, String label) {
    return Semantics(
      header: true,
      label: label,
      child: child,
    );
  }

  /// Announces a message to the screen reader (e.g. after an action).
  static void announce(BuildContext context, String message) {
    SemanticsService.announce(message, Directionality.of(context));
  }

  /// Hides decorative/redundant elements from the accessibility tree.
  static Widget decorative(Widget child) {
    return ExcludeSemantics(child: child);
  }

  /// Groups related elements under one semantic node with a description.
  static Widget group(Widget child, String label) {
    return MergeSemantics(
      child: Semantics(
        label: label,
        child: child,
      ),
    );
  }

  /// Wraps a page content widget with a live region that announces changes.
  static Widget liveRegion(Widget child) {
    return Semantics(
      liveRegion: true,
      child: child,
    );
  }
}

/// An [ExcludeSemantics] wrapper that also hints the hidden content.
/// Use for visual-only decorations that would confuse a screen reader.
class DecorativeImage extends StatelessWidget {
  final Widget child;
  const DecorativeImage({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: child);
}
