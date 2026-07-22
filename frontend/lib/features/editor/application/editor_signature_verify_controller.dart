import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status of a digital signature verification (Phase 43).
enum SignatureVerifyStatus { valid, invalid, unknown, expired, revoked }

/// A verified digital signature entry found in the document (Phase 43).
class VerifiedSignature {
  final String id;
  final String signerName;
  final String? signerEmail;
  final DateTime signedAt;
  final SignatureVerifyStatus status;
  final String? reason;
  final String? location;
  final int? pageIndex;
  final String? certificateIssuer;
  final DateTime? certificateExpiry;
  final String? algorithm;
  final String statusMessage;

  const VerifiedSignature({
    required this.id,
    required this.signerName,
    this.signerEmail,
    required this.signedAt,
    required this.status,
    this.reason,
    this.location,
    this.pageIndex,
    this.certificateIssuer,
    this.certificateExpiry,
    this.algorithm,
    required this.statusMessage,
  });

  bool get isValid => status == SignatureVerifyStatus.valid;
  bool get isTrusted => isValid && certificateIssuer != null;
}

/// UI state for the signature verification panel (Phase 43).
class EditorSignatureVerifyState {
  final bool visible;
  final bool verifying;
  final List<VerifiedSignature> signatures;
  final bool documentModified;
  final String? error;

  const EditorSignatureVerifyState({
    this.visible = false,
    this.verifying = false,
    this.signatures = const [],
    this.documentModified = false,
    this.error,
  });

  int get totalCount => signatures.length;
  int get validCount => signatures.where((s) => s.isValid).length;
  int get invalidCount =>
      signatures.where((s) => s.status == SignatureVerifyStatus.invalid).length;
  bool get allValid => signatures.isNotEmpty && validCount == totalCount;
  bool get hasSignatures => signatures.isNotEmpty;

  EditorSignatureVerifyState copyWith({
    bool? visible,
    bool? verifying,
    List<VerifiedSignature>? signatures,
    bool? documentModified,
    String? error,
    bool clearError = false,
  }) =>
      EditorSignatureVerifyState(
        visible: visible ?? this.visible,
        verifying: verifying ?? this.verifying,
        signatures: signatures ?? this.signatures,
        documentModified: documentModified ?? this.documentModified,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Controller for the digital signature verification panel (Phase 43).
///
/// Verifies all digital signatures embedded in the PDF: checks certificate
/// validity, expiration, and whether the document was modified after signing.
/// Reports per-signature status with signer details and certificate info.
final editorSignatureVerifyProvider = StateNotifierProvider<
    EditorSignatureVerifyController,
    EditorSignatureVerifyState>((ref) => EditorSignatureVerifyController());

class EditorSignatureVerifyController
    extends StateNotifier<EditorSignatureVerifyState> {
  EditorSignatureVerifyController()
      : super(const EditorSignatureVerifyState());

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  /// Begin verification (the actual crypto check is async and platform-dependent;
  /// the screen calls this, performs the check, then calls [setResults]).
  void beginVerify() {
    state = state.copyWith(verifying: true, clearError: true);
  }

  /// Set verification results.
  void setResults(List<VerifiedSignature> sigs, {bool modified = false}) {
    state = state.copyWith(
      verifying: false,
      signatures: sigs,
      documentModified: modified,
    );
  }

  /// Report a verification error.
  void setError(String error) {
    state = state.copyWith(verifying: false, error: error);
  }

  void clear() => state = const EditorSignatureVerifyState();
}
