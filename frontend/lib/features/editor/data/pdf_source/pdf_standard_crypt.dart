import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// AES-CBC of [data] with no padding. [data] must be a multiple of 16 bytes.
/// Shared with the encryptor so a file this app locks opens with the same
/// algorithm that locked it.
Uint8List pdfAesCbcNoPad(Uint8List key, Uint8List iv, Uint8List data, {required bool encrypt}) {
  final c = CBCBlockCipher(AESEngine())..init(encrypt, ParametersWithIV(KeyParameter(key), iv));
  final out = Uint8List(data.length);
  for (var off = 0; off < data.length; off += 16) {
    c.processBlock(data, off, out, off);
  }
  return out;
}

/// Hash algorithm 2.B of ISO 32000-2 (revision 6).
///
/// Each round keeps the full SHA-256, SHA-384 or SHA-512 digest. Truncating
/// the longer digests to 32 bytes makes the hash disagree with other readers.
Uint8List pdfRevision6Hash(Uint8List password, List<int> salt, List<int> udata) {
  var k = Uint8List.fromList(crypto.sha256.convert([...password, ...salt, ...udata]).bytes);
  for (var i = 0;; i++) {
    final round = [...password, ...k, ...udata];
    final k1 = Uint8List(round.length * 64);
    for (var r = 0; r < 64; r++) {
      k1.setRange(r * round.length, (r + 1) * round.length, round);
    }
    final e = pdfAesCbcNoPad(Uint8List.sublistView(k, 0, 16), Uint8List.sublistView(k, 16, 32), k1, encrypt: true);
    var sum = 0;
    for (var j = 0; j < 16; j++) {
      sum += e[j];
    }
    final digest = switch (sum % 3) {
      0 => crypto.sha256,
      1 => crypto.sha384,
      _ => crypto.sha512,
    };
    k = Uint8List.fromList(digest.convert(e).bytes);
    if (i >= 63 && e.last <= i + 1 - 32) break;
  }
  return Uint8List.sublistView(k, 0, 32);
}

/// File key for the standard security handler, AES-256 (PDF 2.0, /V 5 /R 6).
///
/// Streams and strings are a 16-byte IV plus AES-256-CBC with PKCS#7 padding.
/// Revision 6 does not mix the key per object. Callers must not pass strings
/// from the encryption dictionary or cross-reference streams: those are not
/// encrypted.
class PdfFileEncryption {
  PdfFileEncryption(this.fileKey, {required this.encryptMetadata});

  final Uint8List fileKey;

  /// False when the file says /EncryptMetadata false: the metadata stream
  /// stays ciphertext-free and must not be passed to [decryptData].
  final bool encryptMetadata;

  /// [u], [ue], [o], [oe] and [perms] are the raw encryption-dictionary
  /// strings. Returns null for any handler other than revision 6 AES-256, or
  /// when [password] is neither the user nor the owner password.
  ///
  /// An empty password is a real password. It is what opens a file saved
  /// with no user password.
  static PdfFileEncryption? tryUnlock({
    required bool standardHandler,
    required int version,
    required int revision,
    required bool stdCryptFilter,
    required bool aesV3,
    required Uint8List? u,
    required Uint8List? ue,
    required Uint8List? o,
    required Uint8List? oe,
    required Uint8List? perms,
    required bool encryptMetadata,
    required String password,
  }) {
    if (!standardHandler || version != 5 || revision != 6 || !stdCryptFilter || !aesV3) return null;
    if (u == null || u.length < 48 || ue == null || ue.length != 32) return null;
    if (perms == null || perms.length != 16) return null;
    final pw = _password(password);
    Uint8List? key;
    if (_same(pdfRevision6Hash(pw, u.sublist(32, 40), const []), u.sublist(0, 32))) {
      key = pdfAesCbcNoPad(pdfRevision6Hash(pw, u.sublist(40, 48), const []), Uint8List(16), ue, encrypt: false);
    } else if (o != null &&
        o.length >= 48 &&
        oe != null &&
        oe.length == 32 &&
        _same(pdfRevision6Hash(pw, o.sublist(32, 40), u), o.sublist(0, 32))) {
      key = pdfAesCbcNoPad(pdfRevision6Hash(pw, o.sublist(40, 48), u), Uint8List(16), oe, encrypt: false);
    }
    if (key == null || key.length != 32) return null;
    final plainPerms = pdfAesCbcNoPad(key, Uint8List(16), perms, encrypt: false);
    // Bytes 9–11 are the letters 'adb' when the key is right.
    if (plainPerms.length < 12 ||
        plainPerms[8] != 0x54 ||
        plainPerms[9] != 0x61 ||
        plainPerms[10] != 0x64 ||
        plainPerms[11] != 0x62) {
      return null;
    }
    return PdfFileEncryption(key, encryptMetadata: encryptMetadata);
  }

  /// IV + ciphertext → PKCS#7-unpadded plaintext.
  ///
  /// Throws [FormatException] when the bytes are not a padded AES block, so
  /// the caller can refuse the file instead of treating ciphertext as text.
  Uint8List decryptData(Uint8List data) {
    if (data.length < 32 || data.length % 16 != 0) {
      throw const FormatException('Encrypted PDF data is not an AES block.');
    }
    final iv = Uint8List.sublistView(data, 0, 16);
    final body = Uint8List.sublistView(data, 16);
    final plain = pdfAesCbcNoPad(fileKey, iv, body, encrypt: false);
    final n = plain.last;
    if (n < 1 || n > 16) {
      throw const FormatException('Encrypted PDF data has bad padding.');
    }
    for (var i = plain.length - n; i < plain.length; i++) {
      if (plain[i] != n) throw const FormatException('Encrypted PDF data has bad padding.');
    }
    return Uint8List.sublistView(plain, 0, plain.length - n);
  }

  static Uint8List _password(String s) {
    final b = utf8.encode(s);
    return Uint8List.fromList(b.length > 127 ? b.sublist(0, 127) : b);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}
