import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_settings.dart';

enum ConvertFormat { word, excel, ppt }

/// Calls the managed backend to convert a PDF to an Office file. The heavy work
/// happens server-side (see backend /api/v1/convert/*). Requires a configured
/// server (AppSettings.apiBaseUrl / hasCustomServer).
class ConversionService {
  ConversionService._();
  static final ConversionService instance = ConversionService._();

  String _path(ConvertFormat f) {
    switch (f) {
      case ConvertFormat.word:
        return '/convert/pdf-to-word';
      case ConvertFormat.excel:
        return '/convert/pdf-to-excel';
      case ConvertFormat.ppt:
        return '/convert/pdf-to-ppt';
    }
  }

  String _ext(ConvertFormat f) {
    switch (f) {
      case ConvertFormat.word:
        return 'docx';
      case ConvertFormat.excel:
        return 'xlsx';
      case ConvertFormat.ppt:
        return 'pptx';
    }
  }

  /// Whether a real (non-default) backend server is configured.
  bool get serverConfigured => AppSettings.instance.hasCustomServer;

  /// Upload [pdfPath], convert to [format], save the result locally, return its
  /// path. Throws on network / server errors (caller shows a friendly message).
  Future<String> convert(String pdfPath, ConvertFormat format) async {
    final dio = Dio(BaseOptions(
      baseUrl: AppSettings.instance.apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 180),
    ));

    final fileName = pdfPath.split('/').last;
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(pdfPath, filename: fileName),
    });

    final resp = await dio.post(
      _path(format),
      data: form,
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = (resp.data as List<int>);
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/ai_pdf_output');
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final stem = fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outPath = '${outDir.path}/${stem}_$ts.${_ext(format)}';
    await File(outPath).writeAsBytes(bytes);
    return outPath;
  }
}
