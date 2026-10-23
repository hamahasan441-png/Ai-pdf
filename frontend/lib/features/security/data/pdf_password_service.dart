import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:ai_pdf/features/security/data/pdf_encryptor.dart';

/// Offline PDF password protection: AES-256 with the standard security
/// handler (PDF 2.0, /R 6), which Acrobat, Chrome, iOS, Android and every
/// current reader open after asking for the password.
///
/// Earlier builds returned the input unchanged and reported success, so a
/// "protected" file opened without a password. Removing a password is not
/// offered: it needs decryption, which this app does not implement.
class PdfPasswordService {
  const PdfPasswordService();

  /// Encrypted copy of [pdfBytes]. Restricting [access] without an
  /// [ownerPassword] uses a random one, so the limits cannot be lifted by
  /// the person who only knows [password]. Runs off the UI thread.
  Future<Uint8List> protect({
    required Uint8List pdfBytes,
    required String password,
    String? ownerPassword,
    PdfAccess access = const PdfAccess(),
  }) {
    final restricted = !(access.print && access.copy && access.modify && access.annotate);
    final owner = ownerPassword ??
        (restricted ? List.generate(32, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[_secure(32)]).join() : null);
    return Isolate.run(
      () => PdfEncryptor().encrypt(pdfBytes, userPassword: password, ownerPassword: owner, access: access),
    );
  }

  /// Protects the PDF at [sourcePath] and writes `<name>_protected.pdf` to
  /// the app's documents folder, through a temporary file so a failure
  /// leaves nothing half-written. Returns the new path.
  Future<String> protectFile({
    required String sourcePath,
    required String password,
    PdfAccess access = const PdfAccess(),
    Future<Directory> Function()? outputDirectory,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final out = await protect(pdfBytes: bytes, password: password, access: access);
    final dir = await (outputDirectory ?? getApplicationDocumentsDirectory)();
    var base = sourcePath.split(Platform.pathSeparator).last;
    if (base.toLowerCase().endsWith('.pdf')) base = base.substring(0, base.length - 4);
    final path = '${dir.path}/${base}_protected_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final tmp = File('$path.partial');
    try {
      await tmp.writeAsBytes(out, flush: true);
      await tmp.rename(path);
    } catch (_) {
      if (tmp.existsSync()) await tmp.delete();
      rethrow;
    }
    return path;
  }
}

final _rng = Random.secure();
int _secure(int max) => _rng.nextInt(max);
