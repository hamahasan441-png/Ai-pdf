import 'dart:ui' show Offset, Rect;

import 'package:flutter/material.dart' show Color;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Predefined stamp categories.
enum StampKind {
  approved,
  rejected,
  confidential,
  draft,
  finalVersion,
  paid,
  voided,
  urgent,
  copy,
  custom,
}

/// A stamp annotation (APPROVED, CONFIDENTIAL, DRAFT, etc.).
///
/// Stamps render as a bordered rectangle with bold text inside — a standard
/// professional PDF annotation type that every competitor has. Supports both
/// predefined kinds (with localisable display text) and custom user text.
///
/// ### Coordinate system
/// [pos] is the top-left corner in normalised 0..1 page coordinates.
/// [width] / [height] are normalised fractions of the page.
/// [rotation] is in radians.
class StampAnnotation extends EditorAnnotation {
  Offset pos;
  double width;
  double height;
  StampKind kind;
  String customText;
  Color color;
  double rotation;

  StampAnnotation({
    required this.pos,
    required this.width,
    required this.height,
    required this.kind,
    this.customText = '',
    required this.color,
    this.rotation = 0.0,
    super.id,
  });

  /// The display text for this stamp.
  String get displayText {
    switch (kind) {
      case StampKind.approved:
        return 'APPROVED';
      case StampKind.rejected:
        return 'REJECTED';
      case StampKind.confidential:
        return 'CONFIDENTIAL';
      case StampKind.draft:
        return 'DRAFT';
      case StampKind.finalVersion:
        return 'FINAL';
      case StampKind.paid:
        return 'PAID';
      case StampKind.voided:
        return 'VOID';
      case StampKind.urgent:
        return 'URGENT';
      case StampKind.copy:
        return 'COPY';
      case StampKind.custom:
        return customText;
    }
  }

  /// Create a predefined stamp at the center of the page.
  factory StampAnnotation.centered({
    required StampKind kind,
    required Color color,
    String customText = '',
  }) {
    const w = 0.25;
    const h = 0.06;
    return StampAnnotation(
      pos: const Offset(0.5 - w / 2, 0.5 - h / 2),
      width: w,
      height: h,
      kind: kind,
      customText: customText,
      color: color,
    );
  }

  @override
  Rect get bounds => Rect.fromLTWH(pos.dx, pos.dy, width, height);

  @override
  void translate(Offset delta) {
    pos = clampOffset01(pos + delta);
  }

  @override
  void scaleTo(Rect next) {
    pos = Offset(next.left.clamp(0.0, 1.0), next.top.clamp(0.0, 1.0));
    width = next.width.abs().clamp(0.02, 1.0);
    height = next.height.abs().clamp(0.01, 1.0);
  }

  @override
  StampAnnotation clone({double shift = 0, String? id}) {
    final c = StampAnnotation(
      pos: Offset(pos.dx + shift, pos.dy + shift),
      width: width,
      height: height,
      kind: kind,
      customText: customText,
      color: color,
      rotation: rotation,
      id: id,
    );
    c.copyBaseFrom(this);
    return c;
  }

  @override
  void restoreFrom(StampAnnotation o) {
    pos = o.pos;
    width = o.width;
    height = o.height;
    kind = o.kind;
    customText = o.customText;
    color = o.color;
    rotation = o.rotation;
    copyBaseFrom(o);
  }
}
