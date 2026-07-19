import 'dart:ui' show Offset;

import 'package:ai_pdf/features/editor/data/signature_repository.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_signature_picker_sheet.dart';

class EditorSignatureFlowService {
  final SignatureRepository _repository;

  const EditorSignatureFlowService({
    SignatureRepository repository = const SignatureRepository(),
  }) : _repository = repository;

  Future<void> deleteSavedSignature(List<List<Offset>> savedSignatures, int index) async {
    savedSignatures.removeAt(index);
    await _repository.saveSavedSignatures(savedSignatures);
  }

  List<Offset>? resolveSavedSignature(
    SignatureChoiceResult choice,
    List<List<Offset>> savedSignatures,
  ) {
    if (!(choice.action ?? '').startsWith('saved_')) return null;
    final idx = int.tryParse(choice.action!.replaceFirst('saved_', ''));
    if (idx == null || idx >= savedSignatures.length) return null;
    return savedSignatures[idx];
  }

  Future<void> persistDrawnSignatureIfRequested(
    List<List<Offset>> savedSignatures,
    List<Offset>? points,
    bool? save,
  ) async {
    if (points == null || points.length <= 1) return;
    if (save == true) {
      savedSignatures.add(List.from(points));
      await _repository.saveSavedSignatures(savedSignatures);
    }
  }
}
