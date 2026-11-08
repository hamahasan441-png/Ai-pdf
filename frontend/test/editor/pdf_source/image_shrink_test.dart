import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_image_shrinker.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';

void main() {
  test('a large flat image becomes a smaller jpeg and the words stay', () {
    final pdf = _pdf(image: _flateImage(width: 240, height: 180), extra: '');
    final report = shrinkPdfImages(pdf, maxEdge: 60, quality: 60);

    expect(report.seen, 1);
    expect(report.shrunk, 1);
    expect(report.bytes.length, lessThan(pdf.length));
    expect(latin1.decode(report.bytes, allowInvalid: true), contains('KEEP-TEXT'));

    final image = _onlyImage(PdfObjectStore.parse(report.bytes));
    expect(image.width, lessThanOrEqualTo(60));
    expect(image.width, greaterThan(0));
    expect(image.filter, '/DCTDecode');
    expect(PdfObjectStore.parse(report.bytes).pages, hasLength(1));
  });

  test('a picture inside a form xobject is found, a small one is not rewritten', () {
    final small = _pdf(image: _flateImage(width: 16, height: 16), extra: '');
    final untouched = shrinkPdfImages(small, maxEdge: 1600);
    expect(untouched.shrunk, 0);
    expect(identical(untouched.bytes, small), isTrue);

    final nested = _pdf(image: _flateImage(width: 240, height: 120), extra: 'form');
    final report = shrinkPdfImages(nested, maxEdge: 40, quality: 50);
    expect(report.shrunk, 1);
    expect(_onlyImage(PdfObjectStore.parse(report.bytes)).width, lessThanOrEqualTo(40));
    expect(latin1.decode(report.bytes, allowInvalid: true), contains('KEEP-TEXT'));
  });

  test('jpeg photos shrink, and a masked image is left alone', () {
    final photo = img.Image(width: 320, height: 200);
    for (var y = 0; y < photo.height; y++) {
      for (var x = 0; x < photo.width; x++) {
        photo.setPixelRgb(x, y, (x * 3) & 255, (y * 5) & 255, 90);
      }
    }
    final jpg = Uint8List.fromList(img.encodeJpg(photo, quality: 95));
    final pdf = _pdf(image: _jpegImage(jpg, width: 320, height: 200), extra: '');
    final report = shrinkPdfImages(pdf, maxEdge: 80, quality: 60);
    expect(report.shrunk, 1);
    final image = _onlyImage(PdfObjectStore.parse(report.bytes));
    expect(image.width, lessThanOrEqualTo(80));
    expect(image.filter, '/DCTDecode');

    final masked = _pdf(image: _flateImage(width: 240, height: 180), extra: 'mask');
    expect(shrinkPdfImages(masked, maxEdge: 40).shrunk, 0);
  });
}

class _Img {
  final int width;
  final int height;
  final String filter;
  const _Img(this.width, this.height, this.filter);
}

_Img _onlyImage(PdfObjectStore store) {
  _Img? found;
  for (var n = 1; n <= store.maxObjectNumber; n++) {
    final obj = store.object(n);
    final dict = obj?.value;
    if (dict is! PdfDict || dict['/Subtype'] != const PdfName('/Image')) continue;
    final filter = dict['/Filter'];
    found = _Img(
      (dict['/Width'] as PdfNum).toInt(),
      (dict['/Height'] as PdfNum).toInt(),
      filter is PdfName ? filter.name : '',
    );
  }
  expect(found, isNotNull);
  return found!;
}

Uint8List _flateImage({required int width, required int height}) {
  final raw = Uint8List(width * height * 3);
  var state = 0x12345678;
  for (var i = 0; i < raw.length; i++) {
    state = (state * 1664525 + 1013904223) & 0x7fffffff;
    raw[i] = (state >> 8) & 0xFF;
  }
  final encoded = Uint8List.fromList(ZLibCodec().encode(raw));
  return _streamObject(
    '<< /Type /XObject /Subtype /Image /Width $width /Height $height '
    '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length ${encoded.length} >>',
    encoded,
  );
}

Uint8List _jpegImage(Uint8List jpg, {required int width, required int height}) {
  return _streamObject(
    '<< /Type /XObject /Subtype /Image /Width $width /Height $height '
    '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpg.length} >>',
    jpg,
  );
}

Uint8List _streamObject(String dict, Uint8List data) {
  final b = BytesBuilder()
    ..add(latin1.encode('$dict\nstream\n'))
    ..add(data)
    ..add(latin1.encode('\nendstream'));
  return b.toBytes();
}

/// [extra] is `form` to hide the image inside a form, or `mask` to attach a
/// soft mask so the shrinker must refuse it.
Uint8List _pdf({required Uint8List image, required String extra}) {
  const content = 'BT /F1 18 Tf 40 40 Td (KEEP-TEXT) Tj ET\nq 80 0 0 60 30 30 cm /Im0 Do Q';
  final contentBytes = latin1.encode(content);
  final objects = <Uint8List>[
    latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    latin1.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
  ];

  if (extra == 'form') {
    final formBody = latin1.encode('q /Im0 Do Q');
    objects.add(latin1.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 500 400] /Contents 4 0 R '
      '/Resources << /Font << /F1 7 0 R >> /XObject << /Fm0 5 0 R >> >> >>',
    ));
    objects.add(_streamObject('<< /Length ${contentBytes.length} >>', Uint8List.fromList(contentBytes)));
    objects.add(_streamObject(
      '<< /Type /XObject /Subtype /Form /BBox [0 0 240 180] '
      '/Resources << /XObject << /Im0 6 0 R >> >> /Length ${formBody.length} >>',
      Uint8List.fromList(formBody),
    ));
    objects.add(image);
    objects.add(latin1.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'));
  } else if (extra == 'mask') {
    final mask = _flateMask();
    objects.add(latin1.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 500 400] /Contents 4 0 R '
      '/Resources << /Font << /F1 7 0 R >> /XObject << /Im0 5 0 R >> >> >>',
    ));
    objects.add(_streamObject('<< /Length ${contentBytes.length} >>', Uint8List.fromList(contentBytes)));
    // The picture points at a mask, which is the reason to skip it.
    final dict = latin1.decode(image);
    final masked = latin1.encode(dict.replaceFirst('/Subtype /Image', '/Subtype /Image /SMask 6 0 R'));
    objects.add(masked);
    objects.add(mask);
    objects.add(latin1.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'));
  } else {
    objects.add(latin1.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 500 400] /Contents 4 0 R '
      '/Resources << /Font << /F1 6 0 R >> /XObject << /Im0 5 0 R >> >> >>',
    ));
    objects.add(_streamObject('<< /Length ${contentBytes.length} >>', Uint8List.fromList(contentBytes)));
    objects.add(image);
    objects.add(latin1.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'));
  }
  return _assemble(objects);
}

Uint8List _flateMask() {
  final raw = Uint8List(8 * 8);
  raw.fillRange(0, raw.length, 255);
  final encoded = Uint8List.fromList(ZLibCodec().encode(raw));
  return _streamObject(
    '<< /Type /XObject /Subtype /Image /Width 8 /Height 8 '
    '/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length ${encoded.length} >>',
    encoded,
  );
}

Uint8List _assemble(List<Uint8List> objects) {
  final b = BytesBuilder()..add(latin1.encode('%PDF-1.4\n'));
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(b.length);
    b
      ..add(latin1.encode('${i + 1} 0 obj\n'))
      ..add(objects[i])
      ..add(latin1.encode('\nendobj\n'));
  }
  final xref = b.length;
  final t = StringBuffer('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    t.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  t.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  b.add(latin1.encode(t.toString()));
  return b.toBytes();
}
