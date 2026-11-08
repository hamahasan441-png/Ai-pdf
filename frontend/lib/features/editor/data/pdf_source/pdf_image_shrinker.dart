import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/preserving_pdf_writer.dart';

/// Longest edge kept when a picture is larger than this. The page still
/// draws it at the same size; only the stored pixels change.
const int imageShrinkMaxEdge = 1600;

/// JPEG quality used for the replacement. High enough that a photo stays
/// clear, low enough that a scan actually gets smaller.
const int imageShrinkQuality = 72;

/// How many pictures were rewritten. [bytes] is the original when nothing
/// could be made smaller, so a text-only file is not rewritten at all.
class ImageShrinkReport {
  final Uint8List bytes;
  final int seen;
  final int shrunk;

  const ImageShrinkReport({required this.bytes, required this.seen, required this.shrunk});
}

String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Makes large images inside [pdf] smaller and leaves everything else.
///
/// Text, vectors, fonts, links and the page size stay. A picture is drawn
/// by a matrix on the page, so fewer pixels do not move it or flatten the
/// page. Images with a mask, and filters other than JPEG or Flate, are
/// left alone: shrinking those would drop transparency or fail to decode.
ImageShrinkReport shrinkPdfImages(
  Uint8List pdf, {
  int maxEdge = imageShrinkMaxEdge,
  int quality = imageShrinkQuality,
}) {
  final store = PdfObjectStore.parse(pdf);
  final seen = <int>{};
  var images = 0;
  var shrunk = 0;

  void visit(int num, int depth) {
    if (depth > 8 || !seen.add(num)) return;
    final obj = store.object(num);
    final dict = obj?.value;
    if (obj == null || dict is! PdfDict || obj.stream == null) return;
    final subtype = dict['/Subtype'];
    if (subtype == const PdfName('/Form')) {
      _walkResources(store, dict['/Resources'], (n) => visit(n, depth + 1));
      return;
    }
    if (subtype != const PdfName('/Image')) return;
    images++;
    if (_shrinkOne(store, obj, maxEdge: maxEdge, quality: quality)) shrunk++;
  }

  for (final page in store.pages) {
    _walkResources(store, page.attr('/Resources'), (n) => visit(n, 0));
  }
  if (shrunk == 0) return ImageShrinkReport(bytes: pdf, seen: images, shrunk: 0);

  final rewritten = PreservingPdfWriter(store, null).write([
    for (var i = 0; i < store.pages.length; i++) SourcePageSpec(i),
  ]);
  return ImageShrinkReport(bytes: rewritten, seen: images, shrunk: shrunk);
}

void _walkResources(PdfObjectStore store, PdfValue? resources, void Function(int num) visit) {
  final dict = store.resolve(resources);
  if (dict is! PdfDict) return;
  final xobjects = store.resolve(dict['/XObject']);
  if (xobjects is! PdfDict) return;
  for (final value in xobjects.entries.values) {
    if (value is PdfRef) visit(value.num);
  }
}

bool _shrinkOne(PdfObjectStore store, PdfIndirect obj, {required int maxEdge, required int quality}) {
  final dict = obj.value as PdfDict;
  if (_isTrue(dict['/ImageMask']) || dict.containsKey('/SMask') || dict.containsKey('/Mask')) return false;
  final filter = _singleFilter(store, dict);
  if (filter != '/DCTDecode' && filter != '/FlateDecode' && filter != '/Fl') return false;
  final stream = obj.stream;
  if (stream == null || stream.isEmpty) return false;

  final img.Image? decoded;
  if (filter == '/DCTDecode') {
    decoded = img.decodeJpg(stream);
  } else {
    decoded = _decodeFlateImage(store, obj, dict);
  }
  if (decoded == null) return false;

  final long = math.max(decoded.width, decoded.height);
  final bulky = filter != '/DCTDecode' && stream.length > 64 * 1024 && long > 256;
  if (long <= maxEdge && !bulky) return false;

  var next = decoded;
  if (long > maxEdge) {
    next = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxEdge)
        : img.copyResize(decoded, height: maxEdge);
  }
  final jpg = Uint8List.fromList(img.encodeJpg(next, quality: quality.clamp(40, 90)));
  if (jpg.length >= stream.length || jpg.length < 4) return false;

  store.replaceObject(
    obj.num,
    PdfDict({
      ...dict.entries,
      '/Type': const PdfName('/XObject'),
      '/Subtype': const PdfName('/Image'),
      '/Width': PdfNum.of(next.width),
      '/Height': PdfNum.of(next.height),
      '/ColorSpace': const PdfName('/DeviceRGB'),
      '/BitsPerComponent': PdfNum.of(8),
      '/Filter': const PdfName('/DCTDecode'),
      '/Length': PdfNum.of(jpg.length),
    }..remove('/DecodeParms')..remove('/Decode')),
    jpg,
  );
  return true;
}

img.Image? _decodeFlateImage(PdfObjectStore store, PdfIndirect obj, PdfDict dict) {
  final bpc = _intOf(store, dict['/BitsPerComponent']);
  final width = _intOf(store, dict['/Width']);
  final height = _intOf(store, dict['/Height']);
  if (bpc != 8 || width == null || height == null || width < 1 || height < 1) return null;
  final space = store.resolve(dict['/ColorSpace']);
  final channels = switch (space) {
    PdfName(name: '/DeviceRGB') => 3,
    PdfName(name: '/DeviceGray') => 1,
    _ => 0,
  };
  if (channels == 0) return null;
  final Uint8List raw;
  try {
    raw = store.decodeStream(obj);
  } on PdfSourceException {
    return null;
  }
  final need = width * height * channels;
  if (raw.length < need) return null;
  final rgb = channels == 3 ? Uint8List.sublistView(raw, 0, need) : _grayToRgb(raw, width * height);
  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: Uint8List.fromList(rgb).buffer,
    numChannels: 3,
  );
}

Uint8List _grayToRgb(Uint8List gray, int pixels) {
  final out = Uint8List(pixels * 3);
  for (var i = 0; i < pixels; i++) {
    final g = gray[i];
    out[i * 3] = g;
    out[i * 3 + 1] = g;
    out[i * 3 + 2] = g;
  }
  return out;
}

String? _singleFilter(PdfObjectStore store, PdfDict dict) {
  final filter = store.resolve(dict['/Filter']);
  if (filter is PdfName) return filter.name;
  if (filter is PdfArray && filter.items.length == 1) {
    final name = store.resolve(filter.items.first);
    if (name is PdfName) return name.name;
  }
  return null;
}

int? _intOf(PdfObjectStore store, PdfValue? value) {
  final resolved = store.resolve(value);
  return resolved is PdfNum ? resolved.toInt() : null;
}

bool _isTrue(PdfValue? value) => value is PdfBool && value.value;
