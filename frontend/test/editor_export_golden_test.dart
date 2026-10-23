import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/document_identity.dart';

/// Not a pixel test. The pixel goldens for exported pages are in
/// test/golden/export_page_golden_test.dart.
void main() {
  test('a document id does not depend on String.hashCode', () {
    const path = '/storage/emulated/0/Download/sample.pdf';
    final id = stableDocumentId(path);
    expect(id, stableDocumentId(path));
    expect(id, hasLength(16));
    expect(id, isNot(path.hashCode.toRadixString(36)));
  });
}
