import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/annotation_persistence_service.dart';
import 'package:ai_pdf/features/editor/data/document_identity.dart';
import 'package:ai_pdf/features/editor/data/editor_hit_test_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

void main() {
  test('document ids stay stable and do not collide', () {
    expect(stableDocumentId('/docs/a.pdf'), stableDocumentId('/docs/a.pdf'));
    expect(stableDocumentId('/docs/a.pdf'), isNot(stableDocumentId('/docs/b.pdf')));
    expect(stableDocumentId('/docs/a.pdf'), isNot(stableDocumentId('/docs/a.pdf ')));
  });

  test('annotations survive a new service instance', () async {
    final root = Directory.systemTemp.createTempSync('ann-save');
    addTearDown(() => root.deleteSync(recursive: true));
    final service = AnnotationPersistenceService(documentsDirectory: () async => root);
    const path = '/storage/docs/contract.pdf';
    final layer = PageLayer()
      ..items.add(ShapeAnnotation(
        ShapeType.rect,
        const Offset(0.1, 0.2),
        const Offset(0.4, 0.5),
        Colors.black,
        2,
      ));
    await service.save(filePath: path, layers: {0: layer});

    final again = AnnotationPersistenceService(documentsDirectory: () async => root);
    final loaded = await again.loadChecked(path);
    expect(loaded.corrupt, isFalse);
    expect(loaded.layers[0]?.shapes, hasLength(1));
    expect(loaded.layers[0]!.shapes.single.start, const Offset(0.1, 0.2));
  });

  test('a corrupt save is backed up instead of looking empty', () async {
    final root = Directory.systemTemp.createTempSync('ann-bad');
    addTearDown(() => root.deleteSync(recursive: true));
    final service = AnnotationPersistenceService(documentsDirectory: () async => root);
    const path = '/storage/docs/broken.pdf';
    final dir = Directory('${root.path}/annotations')..createSync();
    File('${dir.path}/${stableDocumentId(path)}.json').writeAsStringSync('{');

    final loaded = await service.loadChecked(path);
    expect(loaded.corrupt, isTrue);
    expect(loaded.layers, isEmpty);
    expect(File('${dir.path}/${stableDocumentId(path)}.json').existsSync(), isFalse);
    expect(File('${dir.path}/${stableDocumentId(path)}.json.corrupt').existsSync(), isTrue);
  });

  test('hidden and locked objects are not hit targets', () {
    final hidden = ShapeAnnotation(
      ShapeType.rect,
      const Offset(0.1, 0.1),
      const Offset(0.6, 0.6),
      Colors.red,
      1,
    )..visible = false;
    final locked = ShapeAnnotation(
      ShapeType.rect,
      const Offset(0.1, 0.1),
      const Offset(0.6, 0.6),
      Colors.blue,
      1,
    )..locked = true;
    final open = ShapeAnnotation(
      ShapeType.rect,
      const Offset(0.1, 0.1),
      const Offset(0.6, 0.6),
      Colors.green,
      1,
    );
    const hit = EditorHitTestService();
    expect(hit.hitTest(PageLayer()..items.add(hidden), const Offset(0.3, 0.3)), isNull);
    expect(hit.hitTest(PageLayer()..items.add(locked), const Offset(0.3, 0.3)), isNull);
    expect(hit.hitTest(PageLayer()..items.add(open), const Offset(0.3, 0.3)), same(open));
  });
}
