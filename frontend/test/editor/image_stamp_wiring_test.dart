import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/data/editor_hit_test_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';

void main() {
  group('PageLayer typed getters', () {
    test('expose images and stamps separately', () {
      final layer = PageLayer()
        ..items.addAll([
          TextAnnotation(const Offset(0, 0), 't', Colors.black, 0.04, false),
          ImageAnnotation(
            pos: const Offset(0.1, 0.1),
            width: 0.2,
            height: 0.2,
            bytes: Uint8List.fromList(const [1, 2, 3]),
          ),
          StampAnnotation.centered(kind: StampKind.draft, color: Colors.red),
        ]);
      expect(layer.images, hasLength(1));
      expect(layer.stamps, hasLength(1));
      expect(layer.texts, hasLength(1));
    });
  });

  group('Hit-testing box objects', () {
    test('selects an image / stamp when tapped inside its bounds', () {
      const svc = EditorHitTestService();
      final image = ImageAnnotation(
        pos: const Offset(0.2, 0.2),
        width: 0.3,
        height: 0.2,
        bytes: Uint8List.fromList(const [0]),
      );
      final layer = PageLayer()..items.add(image);
      expect(svc.hitTest(layer, const Offset(0.35, 0.30)), same(image));
      expect(svc.hitTest(layer, const Offset(0.95, 0.95)), isNull);
    });
  });

  group('Image / stamp transforms', () {
    test('image translate + scaleTo + clone', () {
      final im = ImageAnnotation(
        pos: const Offset(0.1, 0.1),
        width: 0.2,
        height: 0.2,
        bytes: Uint8List.fromList(const [9]),
        label: 'Logo',
      );
      im.translate(const Offset(0.1, 0.05));
      expect(im.pos.dx, closeTo(0.2, 1e-9));
      im.scaleTo(const Rect.fromLTWH(0.0, 0.0, 0.5, 0.4));
      expect(im.width, closeTo(0.5, 1e-9));
      expect(im.height, closeTo(0.4, 1e-9));

      // scaleTo moved pos to (0,0); clone shifts it by +0.03.
      final dup = im.clone(shift: 0.03) as ImageAnnotation;
      expect(dup.id, isNot(im.id));
      expect(dup.label, 'Logo');
      expect(dup.pos.dx, closeTo(0.03, 1e-9));
    });
  });

  group('Serialization round-trips (Phase 2)', () {
    test('ImageAnnotation preserves bytes / geometry / base props', () {
      final im = ImageAnnotation(
        pos: const Offset(0.15, 0.25),
        width: 0.4,
        height: 0.3,
        bytes: Uint8List.fromList(List<int>.generate(32, (i) => i)),
        rotation: 0.5,
        label: 'Photo',
      )..opacity = 0.8;

      final restored = annotationFromJson(annotationToJson(im))! as ImageAnnotation;
      expect(restored.pos.dx, closeTo(0.15, 1e-9));
      expect(restored.width, closeTo(0.4, 1e-9));
      expect(restored.height, closeTo(0.3, 1e-9));
      expect(restored.rotation, closeTo(0.5, 1e-9));
      expect(restored.label, 'Photo');
      expect(restored.opacity, 0.8);
      expect(restored.bytes, equals(im.bytes));
    });

    test('StampAnnotation preserves kind / color / geometry', () {
      final st = StampAnnotation(
        pos: const Offset(0.3, 0.4),
        width: 0.25,
        height: 0.06,
        kind: StampKind.confidential,
        color: Colors.red,
        rotation: 0.1,
      );
      final restored = annotationFromJson(annotationToJson(st))! as StampAnnotation;
      expect(restored.kind, StampKind.confidential);
      expect(restored.color.value, Colors.red.value);
      expect(restored.width, closeTo(0.25, 1e-9));
      expect(restored.rotation, closeTo(0.1, 1e-9));
      expect(restored.displayText, 'CONFIDENTIAL');
    });
  });
}
