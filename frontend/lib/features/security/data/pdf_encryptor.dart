import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_standard_crypt.dart';

/// What a reader may do with the file without the owner password
/// (ISO 32000-2 Table 22).
class PdfAccess {
  final bool print;
  final bool copy;
  final bool modify;
  final bool annotate;

  const PdfAccess({this.print = true, this.copy = true, this.modify = true, this.annotate = true});

  /// The /P value: reserved bits 7, 8 and 13–32 set, bits 1–2 clear.
  int get pValue {
    var p = 0xFFFFF0C0; // reserved high bits and 7–8
    if (print) p |= 1 << 2 | 1 << 11; // print, high-quality print
    if (modify) p |= 1 << 3 | 1 << 10; // modify, assemble
    if (copy) p |= 1 << 4 | 1 << 9; // copy, extract for accessibility
    if (annotate) p |= 1 << 5 | 1 << 8; // annotate, fill forms
    return p.toSigned(32);
  }
}

/// Encrypts a PDF with the standard security handler, AES-256 (PDF 2.0,
/// /V 5 /R 6). Readers ask for [userPassword] before showing anything; the
/// owner password lifts the [PdfAccess] limits.
///
/// Every string and stream is encrypted with AES-256-CBC under a random
/// file key and a random IV. The file is rewritten in full (classic xref,
/// no object streams), so no unencrypted copy of an object remains.
class PdfEncryptor {
  PdfEncryptor({Random? random}) : _rnd = random ?? Random.secure();

  final Random _rnd;

  Uint8List encrypt(
    Uint8List pdf, {
    required String userPassword,
    String? ownerPassword,
    PdfAccess access = const PdfAccess(),
  }) {
    if (userPassword.isEmpty) throw ArgumentError('A password is required.');
    final store = PdfObjectStore.parse(pdf);
    // An empty user password is opened by the parser. Encrypting it again
    // would nest a second encryption dictionary around plaintext we just
    // decrypted, so an already-encrypted file is still refused.
    if (store.wasEncrypted) {
      throw const PdfSourceException('The PDF is encrypted.', encrypted: true);
    }
    final user = _pw(userPassword);
    final owner = _pw(ownerPassword == null || ownerPassword.isEmpty ? userPassword : ownerPassword);
    final fileKey = _bytes(32);

    final uvs = _bytes(8), uks = _bytes(8);
    final u = Uint8List.fromList([...pdfRevision6Hash(user, uvs, const []), ...uvs, ...uks]);
    final ue = pdfAesCbcNoPad(pdfRevision6Hash(user, uks, const []), Uint8List(16), fileKey, encrypt: true);
    final ovs = _bytes(8), oks = _bytes(8);
    final o = Uint8List.fromList([...pdfRevision6Hash(owner, ovs, u), ...ovs, ...oks]);
    final oe = pdfAesCbcNoPad(pdfRevision6Hash(owner, oks, u), Uint8List(16), fileKey, encrypt: true);
    final p = access.pValue;
    final permsPlain = Uint8List.fromList([
      p & 0xFF, p >> 8 & 0xFF, p >> 16 & 0xFF, p >> 24 & 0xFF, //
      0xFF, 0xFF, 0xFF, 0xFF, 0x54, 0x61, 0x64, 0x62, ..._bytes(4),
    ]);
    final ecb = ECBBlockCipher(AESEngine())..init(true, KeyParameter(fileKey));
    final perms = Uint8List(16);
    ecb.processBlock(permsPlain, 0, perms, 0);

    final out = BytesBuilder(copy: false);
    out.add(latin1.encode('%PDF-2.0\n'));
    out.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final offsets = <int, (int, int)>{}; // num → (offset, gen)
    PdfRef? keep(PdfRef r) => r;

    for (var n = 1; n <= store.maxObjectNumber; n++) {
      final obj = store.object(n);
      if (obj == null) continue;
      var value = obj.value;
      if (value is PdfDict) {
        final type = value['/Type'];
        if (type == const PdfName('/XRef') || type == const PdfName('/ObjStm')) continue;
      }
      // A signature's /Contents is not encrypted (ISO 32000-2 §7.6.2); the
      // signature itself would not survive the rewrite anyway.
      final sig = value is PdfDict && value['/Type'] == const PdfName('/Sig');
      value = sig ? value : _encryptValue(value, fileKey);
      Uint8List? stream = obj.stream;
      if (stream != null) {
        stream = _aesCbc(fileKey, stream);
        if (value is PdfDict) value = PdfDict({...value.entries, '/Length': PdfNum.of(stream.length)});
      }
      offsets[n] = (out.length, obj.gen);
      out.add(latin1.encode('$n ${obj.gen} obj\n'));
      writePdfValue(out, value, keep);
      if (stream != null) {
        out.add(latin1.encode('\nstream\n'));
        out.add(stream);
        out.add(latin1.encode('\nendstream'));
      }
      out.add(latin1.encode('\nendobj\n'));
    }

    final encNum = store.maxObjectNumber + 1;
    offsets[encNum] = (out.length, 0);
    out.add(latin1.encode('$encNum 0 obj\n'));
    writePdfValue(
      out,
      PdfDict({
        '/Filter': const PdfName('/Standard'),
        '/V': PdfNum.of(5),
        '/R': PdfNum.of(6),
        '/Length': PdfNum.of(256),
        '/CF': const PdfDict({
          '/StdCF': PdfDict({
            '/AuthEvent': PdfName('/DocOpen'),
            '/CFM': PdfName('/AESV3'),
            '/Length': PdfNum('32'),
          }),
        }),
        '/StmF': const PdfName('/StdCF'),
        '/StrF': const PdfName('/StdCF'),
        '/O': _hex(o),
        '/U': _hex(u),
        '/OE': _hex(oe),
        '/UE': _hex(ue),
        '/Perms': _hex(perms),
        '/P': PdfNum.of(p),
        '/EncryptMetadata': const PdfBool(true),
      }),
      keep,
    );
    out.add(latin1.encode('\nendobj\n'));

    final size = encNum + 1;
    final xref = out.length;
    final x = StringBuffer('xref\n0 $size\n0000000000 65535 f \n');
    for (var n = 1; n < size; n++) {
      final e = offsets[n];
      x.write(e == null
          ? '0000000000 00000 f \n'
          : '${e.$1.toString().padLeft(10, '0')} ${e.$2.toString().padLeft(5, '0')} n \n');
    }
    out.add(latin1.encode(x.toString()));
    final id = store.trailer['/ID'];
    final trailer = <String, PdfValue>{
      '/Size': PdfNum.of(size),
      '/Root': store.trailer['/Root']!,
      if (store.trailer['/Info'] case final PdfRef info) '/Info': info,
      '/Encrypt': PdfRef(encNum, 0),
      '/ID': id is PdfArray && id.items.length == 2
          ? id
          : PdfArray([_hex(_bytes(16)), _hex(_bytes(16))]),
    };
    out.add(latin1.encode('trailer\n'));
    writePdfValue(out, PdfDict(trailer), keep);
    out.add(latin1.encode('\nstartxref\n$xref\n%%EOF\n'));
    return out.toBytes();
  }

  PdfValue _encryptValue(PdfValue v, Uint8List key) => switch (v) {
        PdfString() => _hex(_aesCbc(key, v.bytes)),
        PdfArray(:final items) => PdfArray([for (final i in items) _encryptValue(i, key)]),
        PdfDict(:final entries) => PdfDict({for (final e in entries.entries) e.key: _encryptValue(e.value, key)}),
        _ => v,
      };

  /// IV + AES-256-CBC(PKCS#7 padded [data]).
  Uint8List _aesCbc(Uint8List key, Uint8List data) {
    final iv = _bytes(16);
    final pad = 16 - data.length % 16;
    final padded = Uint8List(data.length + pad)
      ..setRange(0, data.length, data)
      ..fillRange(data.length, data.length + pad, pad);
    return Uint8List.fromList([...iv, ...pdfAesCbcNoPad(key, iv, padded, encrypt: true)]);
  }

  Uint8List _bytes(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) _rnd.nextInt(256)]);
}

/// UTF-8 password, cut to 127 bytes as the standard asks. (SASLprep
/// normalization is not applied; passwords are used as typed.)
Uint8List _pw(String s) {
  final b = utf8.encode(s);
  return Uint8List.fromList(b.length > 127 ? b.sublist(0, 127) : b);
}

PdfString _hex(List<int> bytes) {
  final b = StringBuffer('<');
  for (final x in bytes) {
    b.write(x.toRadixString(16).padLeft(2, '0'));
  }
  b.write('>');
  return PdfString(Uint8List.fromList(latin1.encode(b.toString())));
}
