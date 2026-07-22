import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_signature_verify_controller.dart';

/// Panel showing digital signature verification results (Phase 43).
///
/// Displays each signature with signer info, certificate details, and a
/// validity badge. A header banner shows overall document integrity status.
class EditorSignatureVerifyPanel extends StatelessWidget {
  final EditorSignatureVerifyState verifyState;
  final VoidCallback onVerify;
  final VoidCallback onClose;
  final ValueChanged<int>? onJumpToPage;

  const EditorSignatureVerifyPanel({
    super.key,
    required this.verifyState,
    required this.onVerify,
    required this.onClose,
    this.onJumpToPage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(12),
        bottomLeft: Radius.circular(12),
      ),
      color: cs.surface,
      child: SizedBox(
        width: 300,
        child: Column(
          children: [
            _header(cs),
            if (verifyState.hasSignatures) _integrityBanner(cs),
            const Divider(height: 1),
            Expanded(
              child: verifyState.verifying
                  ? const Center(child: CircularProgressIndicator())
                  : verifyState.hasSignatures
                      ? ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: verifyState.signatures.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) =>
                              _sigRow(verifyState.signatures[i], cs),
                        )
                      : _empty(cs),
            ),
            _footer(cs),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.verified_user, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Signatures',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
          if (verifyState.hasSignatures) ...[
            const Spacer(),
            _badge('${verifyState.validCount} valid', Colors.green),
            if (verifyState.invalidCount > 0) ...[
              const SizedBox(width: 4),
              _badge('${verifyState.invalidCount} invalid', Colors.red),
            ],
          ] else
            const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _integrityBanner(ColorScheme cs) {
    final allValid = verifyState.allValid && !verifyState.documentModified;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: allValid
          ? Colors.green.withOpacity(0.1)
          : Colors.red.withOpacity(0.1),
      child: Row(
        children: [
          Icon(
            allValid ? Icons.shield : Icons.warning,
            size: 16,
            color: allValid ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              allValid
                  ? 'Document integrity verified'
                  : verifyState.documentModified
                      ? 'Document modified after signing'
                      : 'Some signatures are invalid',
              style: TextStyle(
                fontSize: 12,
                color: allValid ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sigRow(VerifiedSignature sig, ColorScheme cs) {
    return InkWell(
      onTap: sig.pageIndex != null ? () => onJumpToPage?.call(sig.pageIndex!) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(sig.status), size: 20, color: _statusColor(sig.status)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sig.signerName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          )),
                      if (sig.signerEmail != null)
                        Text(sig.signerEmail!,
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (sig.pageIndex != null)
                  Text('p.${sig.pageIndex! + 1}',
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            Text(sig.statusMessage,
                style: TextStyle(
                  fontSize: 11,
                  color: _statusColor(sig.status),
                )),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                _detail('Signed', _fmtDate(sig.signedAt)),
                if (sig.certificateIssuer != null)
                  _detail('Issuer', sig.certificateIssuer!),
                if (sig.algorithm != null)
                  _detail('Algorithm', sig.algorithm!),
                if (sig.reason != null)
                  _detail('Reason', sig.reason!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Text(
      '$label: $value',
      style: const TextStyle(fontSize: 10, color: Colors.grey),
    );
  }

  Widget _empty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.security, size: 48, color: cs.onSurfaceVariant.withOpacity(0.3)),
          const SizedBox(height: 8),
          Text('No digital signatures found',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Tap "Verify" to check',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Verify', style: TextStyle(fontSize: 12)),
        onPressed: verifyState.verifying ? null : onVerify,
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }

  IconData _statusIcon(SignatureVerifyStatus s) {
    switch (s) {
      case SignatureVerifyStatus.valid:
        return Icons.check_circle;
      case SignatureVerifyStatus.invalid:
        return Icons.cancel;
      case SignatureVerifyStatus.expired:
        return Icons.schedule;
      case SignatureVerifyStatus.revoked:
        return Icons.block;
      case SignatureVerifyStatus.unknown:
        return Icons.help;
    }
  }

  Color _statusColor(SignatureVerifyStatus s) {
    switch (s) {
      case SignatureVerifyStatus.valid:
        return Colors.green;
      case SignatureVerifyStatus.invalid:
      case SignatureVerifyStatus.revoked:
        return Colors.red;
      case SignatureVerifyStatus.expired:
        return Colors.orange;
      case SignatureVerifyStatus.unknown:
        return Colors.grey;
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}
