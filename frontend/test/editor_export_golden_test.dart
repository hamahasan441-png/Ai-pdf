import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/document_identity.dart';

/// Pixel golden comparisons still need the corpus PDFs under test/golden/corpus.
/// This file no longer passes on an empty assertion.
void main() {
  test('a document id does not depend on String.hashCode', () {
    const path = '/storage/emulated/0/Download/sample.pdf';
    final id = stableDocumentId(path);
    expect(id, stableDocumentId(path));
    expect(id, hasLength(16));
    expect(id, isNot(path.hashCode.toRadixString(36)));
  });
}
