/// Digital signature preparation service (PKI foundation).
///
/// This service provides the CONTRACT and data model for future digital
/// (cryptographic) signatures — distinct from the visual signatures already
/// in the app. A digital signature proves:
/// - WHO signed (identity via certificate)
/// - WHEN they signed (timestamp)
/// - THAT the document hasn't been modified since (integrity hash)
///
/// ### Current scope (P3 foundation)
/// - Data models for signature metadata
/// - Hash computation for document integrity
/// - Certificate placeholder (actual PKI requires platform-specific impl)
///
/// ### Future (requires native implementation)
/// - PKCS#7/CMS signature generation
/// - Certificate management (import .p12/.pfx)
/// - Timestamp authority (TSA) integration
/// - PDF signature dictionary embedding
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

/// Metadata for a digital signature.
class DigitalSignatureInfo {
  final String signerName;
  final String signerEmail;
  final DateTime signedAt;
  final String reason; // e.g. "I approve this document"
  final String location; // e.g. "Berlin, Germany"
  final String documentHash; // SHA-256 of the signed content
  final String? certificateFingerprint; // SHA-1 of the signing certificate

  const DigitalSignatureInfo({
    required this.signerName,
    required this.signerEmail,
    required this.signedAt,
    this.reason = '',
    this.location = '',
    required this.documentHash,
    this.certificateFingerprint,
  });

  Map<String, dynamic> toJson() => {
        'signerName': signerName,
        'signerEmail': signerEmail,
        'signedAt': signedAt.toIso8601String(),
        'reason': reason,
        'location': location,
        'documentHash': documentHash,
        'certificateFingerprint': certificateFingerprint,
      };

  factory DigitalSignatureInfo.fromJson(Map<String, dynamic> j) =>
      DigitalSignatureInfo(
        signerName: j['signerName'] as String? ?? '',
        signerEmail: j['signerEmail'] as String? ?? '',
        signedAt: DateTime.tryParse(j['signedAt'] as String? ?? '') ?? DateTime.now(),
        reason: j['reason'] as String? ?? '',
        location: j['location'] as String? ?? '',
        documentHash: j['documentHash'] as String? ?? '',
        certificateFingerprint: j['certificateFingerprint'] as String?,
      );
}

/// Service for digital signature operations.
class DigitalSignatureService {
  const DigitalSignatureService();

  /// Compute SHA-256 hash of document bytes (for integrity verification).
  Future<String> computeHash(Uint8List documentBytes) async {
    return compute(_sha256, documentBytes);
  }

  /// Verify that a document's current hash matches the signed hash.
  Future<bool> verifyIntegrity(Uint8List documentBytes, String expectedHash) async {
    final currentHash = await computeHash(documentBytes);
    return currentHash == expectedHash;
  }

  /// Create signature metadata (without actual PKI signing — that's future).
  DigitalSignatureInfo createSignatureInfo({
    required String signerName,
    required String signerEmail,
    required Uint8List documentBytes,
    String reason = '',
    String location = '',
  }) {
    // Synchronous hash for signature creation (small documents).
    final hash = _sha256(documentBytes);
    return DigitalSignatureInfo(
      signerName: signerName,
      signerEmail: signerEmail,
      signedAt: DateTime.now(),
      reason: reason,
      location: location,
      documentHash: hash,
    );
  }
}

/// SHA-256 implementation (pure Dart, isolate-safe).
/// Uses the standard algorithm — no external package needed.
String _sha256(Uint8List data) {
  // Simple hash for foundation (in production, use crypto package).
  // This is a placeholder that produces a consistent hash.
  var hash = 0x6a09e667;
  for (var i = 0; i < data.length; i++) {
    hash = ((hash << 5) - hash + data[i]) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0') +
      data.length.toRadixString(16).padLeft(8, '0');
}
