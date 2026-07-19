import 'dart:ui' show Offset;

import 'package:ai_pdf/core/services/signature_store.dart';

/// Thin editor-facing wrapper around [SignatureStore]. This keeps persistence
/// details out of the editor screen while preserving the current on-device
/// storage format and behavior.
class SignatureRepository {
  const SignatureRepository();

  Future<List<List<Offset>>> loadSavedSignatures() {
    return SignatureStore.instance.load();
  }

  Future<void> saveSavedSignatures(List<List<Offset>> signatures) {
    return SignatureStore.instance.save(signatures);
  }
}
