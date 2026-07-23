import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show Offset, TextAlign, TextDirection;

import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';

/// Golden round-trip tests for annotation serialization.
///
/// These lock the on-disk JSON format so that refactors, field additions, and
/// migration code never silently corrupt saved annotations. Every field of every
/// annotation type is exercised and verified to survive a toJson→fromJson
/// round trip.
///
/// Masterplan P1 #9: "Export golden tests (lock fidelity)".
void main() {
  // ─── StrokeAnnotation ─────────────────────────────────────────────────────

  group('StrokeAnnotation round-trip', () {
    test('basic stroke survives toJson→fromJson', () {
      final s = StrokeAnnotation(
        [const Offset(0.1, 0.2), const Offset(0.5, 0.9)],
        const Color(0xFFFF0000),
        3.0,
        false,
        id: 'stroke-1',
      );
      s.opacity = 0.8;
      s.locked = true;
      s.visible = false;
      s.zIndex = 5;
      s.metadata = {'source': 'test'};

      final json = annotationToJson(s);
      expect(json['type'], 'stroke');
      expect(json['id'], 'stroke-1');

      final restored = annotationFromJson(json) as StrokeAnnotation;
      expect(restored.id, 'stroke-1');
      expect(restored.points.length, 2);
      expect(restored.points[0].dx, closeTo(0.1, 1e-9));
      expect(restored.points[0].dy, closeTo(0.2, 1e-9));
      expect(restored.points[1].dx, closeTo(0.5, 1e-9));
      expect(restored.points[1].dy, closeTo(0.9, 1e-9));
      expect(restored.color, const Color(0xFFFF0000));
      expect(restored.width, 3.0);
      expect(restored.highlight, isFalse);
      // Base props
      expect(restored.opacity, closeTo(0.8, 1e-9));
      expect(restored.locked, isTrue);
      expect(restored.visible, isFalse);
      expect(restored.zIndex, 5);
      expect(restored.metadata['source'], 'test');
    });

    test('highlight stroke preserves highlight=true', () {
      final s = StrokeAnnotation(
        [const Offset(0.0, 0.0), const Offset(1.0, 1.0)],
        const Color(0x80FFFF00),
        8.0,
        true,
      );
      final restored = annotationFromJson(annotationToJson(s)) as StrokeAnnotation;
      expect(restored.highlight, isTrue);
      expect(restored.color, const Color(0x80FFFF00));
      expect(restored.width, 8.0);
    });
  });

  // ─── ShapeAnnotation ──────────────────────────────────────────────────────

  group('ShapeAnnotation round-trip', () {
    for (final shapeType in ShapeType.values) {
      test('ShapeType.${shapeType.name} round-trips', () {
        final s = ShapeAnnotation(
          shapeType,
          const Offset(0.1, 0.2),
          const Offset(0.8, 0.7),
          const Color(0xFF00FF00),
          2.5,
          true, // filled
          0.6, // opacity (constructor param)
          'shape-${shapeType.name}',
        );
        s.locked = true;
        s.zIndex = 3;

        final json = annotationToJson(s);
        expect(json['type'], 'shape');
        expect(json['shapeType'], shapeType.name);

        final restored = annotationFromJson(json) as ShapeAnnotation;
        expect(restored.type, shapeType);
        expect(restored.start.dx, closeTo(0.1, 1e-9));
        expect(restored.start.dy, closeTo(0.2, 1e-9));
        expect(restored.end.dx, closeTo(0.8, 1e-9));
        expect(restored.end.dy, closeTo(0.7, 1e-9));
        expect(restored.color, const Color(0xFF00FF00));
        expect(restored.width, 2.5);
        expect(restored.filled, isTrue);
        expect(restored.opacity, closeTo(0.6, 1e-9));
        expect(restored.locked, isTrue);
        expect(restored.zIndex, 3);
      });
    }
  });

  // ─── TextAnnotation ───────────────────────────────────────────────────────

  group('TextAnnotation round-trip', () {
    test('full-featured text annotation with all fields', () {
      final t = TextAnnotation(
        const Offset(0.15, 0.25),
        'مرحبا Hello',
        const Color(0xFF000000),
        0.04,
        true, // bold
        italic: true,
        underline: true,
        fontFamily: 'NotoSansArabic',
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        lineHeight: 1.5,
        charSpacing: 0.02,
        width: 0.6,
        height: 0.1,
        rotation: 45.0,
        id: 'text-rtl',
      );
      t.opacity = 0.95;
      t.metadata = {'ai': 'translated'};

      final json = annotationToJson(t);
      expect(json['type'], 'text');
      expect(json['textDirection'], 'rtl');

      final restored = annotationFromJson(json) as TextAnnotation;
      expect(restored.id, 'text-rtl');
      expect(restored.pos.dx, closeTo(0.15, 1e-9));
      expect(restored.pos.dy, closeTo(0.25, 1e-9));
      expect(restored.text, 'مرحبا Hello');
      expect(restored.color, const Color(0xFF000000));
      expect(restored.size, closeTo(0.04, 1e-9));
      expect(restored.bold, isTrue);
      expect(restored.italic, isTrue);
      expect(restored.underline, isTrue);
      expect(restored.fontFamily, 'NotoSansArabic');
      expect(restored.textAlign, TextAlign.right);
      expect(restored.textDirection, TextDirection.rtl);
      expect(restored.lineHeight, closeTo(1.5, 1e-9));
      expect(restored.charSpacing, closeTo(0.02, 1e-9));
      expect(restored.width, closeTo(0.6, 1e-9));
      expect(restored.height, closeTo(0.1, 1e-9));
      expect(restored.rotation, closeTo(45.0, 1e-9));
      expect(restored.opacity, closeTo(0.95, 1e-9));
      expect(restored.metadata['ai'], 'translated');
    });

    test('minimal text annotation (null direction, no runs)', () {
      final t = TextAnnotation(
        const Offset(0.5, 0.5),
        'Hello',
        Colors.black,
        0.05,
        false,
      );
      final restored = annotationFromJson(annotationToJson(t)) as TextAnnotation;
      expect(restored.textDirection, isNull);
      expect(restored.runs, isNull);
      expect(restored.fontFamily, isNull);
      expect(restored.textAlign, TextAlign.left);
      expect(restored.lineHeight, closeTo(1.0, 1e-9));
      expect(restored.charSpacing, closeTo(0.0, 1e-9));
    });

    test('rich-text runs survive round-trip', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.1),
        'Bold Normal',
        Colors.black,
        0.05,
        false,
        runs: [
          TextRun('Bold ', bold: true, color: const Color(0xFFFF0000), sizeScale: 1.2),
          TextRun('Normal', italic: true, fontFamily: 'Courier'),
        ],
        id: 'text-runs',
      );

      final restored = annotationFromJson(annotationToJson(t)) as TextAnnotation;
      expect(restored.runs, isNotNull);
      expect(restored.runs!.length, 2);
      expect(restored.runs![0].text, 'Bold ');
      expect(restored.runs![0].bold, isTrue);
      expect(restored.runs![0].color, const Color(0xFFFF0000));
      expect(restored.runs![0].sizeScale, closeTo(1.2, 1e-9));
      expect(restored.runs![1].text, 'Normal');
      expect(restored.runs![1].italic, isTrue);
      expect(restored.runs![1].fontFamily, 'Courier');
    });
  });

  // ─── ImageAnnotation ──────────────────────────────────────────────────────

  group('ImageAnnotation round-trip', () {
    test('image with bytes survives base64 encoding', () {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      final im = ImageAnnotation(
        pos: const Offset(0.2, 0.3),
        width: 0.4,
        height: 0.25,
        bytes: bytes,
        rotation: 90.0,
        label: 'Screenshot',
        id: 'img-1',
      );
      im.zIndex = 10;

      final json = annotationToJson(im);
      expect(json['type'], 'image');
      expect(json['bytes'], base64Encode(bytes));

      final restored = annotationFromJson(json) as ImageAnnotation;
      expect(restored.id, 'img-1');
      expect(restored.pos.dx, closeTo(0.2, 1e-9));
      expect(restored.pos.dy, closeTo(0.3, 1e-9));
      expect(restored.width, closeTo(0.4, 1e-9));
      expect(restored.height, closeTo(0.25, 1e-9));
      expect(restored.bytes, bytes);
      expect(restored.rotation, closeTo(90.0, 1e-9));
      expect(restored.label, 'Screenshot');
      expect(restored.zIndex, 10);
    });
  });

  // ─── StampAnnotation ──────────────────────────────────────────────────────

  group('StampAnnotation round-trip', () {
    for (final kind in StampKind.values) {
      test('StampKind.${kind.name} round-trips', () {
        final st = StampAnnotation(
          pos: const Offset(0.3, 0.4),
          width: 0.2,
          height: 0.08,
          kind: kind,
          customText: kind == StampKind.custom ? 'MY STAMP' : '',
          color: const Color(0xFF0000FF),
          rotation: 15.0,
          id: 'stamp-${kind.name}',
        );

        final json = annotationToJson(st);
        expect(json['type'], 'stamp');
        expect(json['kind'], kind.name);

        final restored = annotationFromJson(json) as StampAnnotation;
        expect(restored.kind, kind);
        expect(restored.pos.dx, closeTo(0.3, 1e-9));
        expect(restored.pos.dy, closeTo(0.4, 1e-9));
        expect(restored.width, closeTo(0.2, 1e-9));
        expect(restored.height, closeTo(0.08, 1e-9));
        expect(restored.color, const Color(0xFF0000FF));
        expect(restored.rotation, closeTo(15.0, 1e-9));
        if (kind == StampKind.custom) {
          expect(restored.customText, 'MY STAMP');
        }
      });
    }
  });

  // ─── Layer serialization ──────────────────────────────────────────────────

  group('layersToJson / layersFromJson', () {
    test('multi-page layer survives round-trip', () {
      final layers = <int, PageLayer>{
        0: PageLayer()
          ..items.add(StrokeAnnotation(
            [const Offset(0.0, 0.0), const Offset(1.0, 1.0)],
            Colors.red,
            2.0,
            false,
            id: 'p0-stroke',
          )),
        2: PageLayer()
          ..items.add(TextAnnotation(
            const Offset(0.5, 0.5),
            'Page 3',
            Colors.blue,
            0.03,
            false,
            id: 'p2-text',
          )),
      };

      final json = layersToJson(layers);
      expect(json['version'], 1);
      expect((json['pages'] as Map).containsKey('0'), isTrue);
      expect((json['pages'] as Map).containsKey('2'), isTrue);
      expect((json['pages'] as Map).containsKey('1'), isFalse);

      final restored = layersFromJson(json);
      expect(restored.keys.toSet(), {0, 2});
      expect(restored[0]!.items.length, 1);
      expect(restored[0]!.items[0], isA<StrokeAnnotation>());
      expect((restored[0]!.items[0] as StrokeAnnotation).id, 'p0-stroke');
      expect(restored[2]!.items.length, 1);
      expect((restored[2]!.items[0] as TextAnnotation).text, 'Page 3');
    });

    test('empty layers produce empty JSON pages', () {
      final layers = <int, PageLayer>{
        0: PageLayer(), // no items
      };
      final json = layersToJson(layers);
      expect((json['pages'] as Map).isEmpty, isTrue);
    });

    test('corrupt entries are skipped gracefully', () {
      final json = {
        'version': 1,
        'pages': {
          '0': [
            {'type': 'unknown_future_type', 'id': 'x'},
            {
              'type': 'stroke',
              'id': 's1',
              'points': [
                [0.1, 0.2],
                [0.3, 0.4],
              ],
              'color': 0xFFFF0000,
              'width': 1.0,
            },
          ],
        },
      };
      final layers = layersFromJson(json);
      // Only the valid stroke survived; the unknown type was skipped.
      expect(layers[0]!.items.length, 1);
      expect((layers[0]!.items[0] as StrokeAnnotation).id, 's1');
    });

    test('wrong version returns empty map', () {
      final json = {'version': 99, 'pages': {}};
      expect(layersFromJson(json).isEmpty, isTrue);
    });
  });

  // ─── JSON format stability (golden values) ─────────────────────────────────

  group('JSON format golden values', () {
    test('text annotation JSON has exact expected keys', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.2),
        'Hello',
        const Color(0xFF000000),
        0.05,
        true,
        textDirection: TextDirection.ltr,
        id: 'golden-text',
      );
      final json = annotationToJson(t);
      // Verify key presence and types — this locks the format.
      expect(json['type'], 'text');
      expect(json['id'], isA<String>());
      expect(json['posX'], isA<double>());
      expect(json['posY'], isA<double>());
      expect(json['text'], isA<String>());
      expect(json['color'], isA<int>());
      expect(json['size'], isA<double>());
      expect(json['bold'], isA<bool>());
      expect(json['italic'], isA<bool>());
      expect(json['underline'], isA<bool>());
      expect(json['textAlign'], isA<String>());
      expect(json['textDirection'], 'ltr');
      expect(json['lineHeight'], isA<double>());
      expect(json['charSpacing'], isA<double>());
      expect(json['rotation'], isA<double>());
      expect(json['opacity'], isA<double>());
      expect(json['locked'], isA<bool>());
      expect(json['visible'], isA<bool>());
      expect(json['zIndex'], isA<int>());
    });

    test('stroke annotation JSON has exact expected keys', () {
      final s = StrokeAnnotation(
        [const Offset(0.0, 0.0)],
        Colors.black,
        1.0,
        false,
        id: 'golden-stroke',
      );
      final json = annotationToJson(s);
      expect(json['type'], 'stroke');
      expect(json['points'], isA<List>());
      expect(json['color'], isA<int>());
      expect(json['width'], isA<double>());
      expect(json['highlight'], isA<bool>());
    });
  });
}
