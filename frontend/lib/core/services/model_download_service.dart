import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Model download service — E2.1B Hybrid ONNX Download (Phase 7).
///
/// Downloads MiniLM-L6-v2 quantized 20MB model as optional download via parallel range download
/// (5 strategies already in Import File tool — GenericFileDownloader Kotlin).
/// For Dart MVP, we use Dio with range support and resume.
///
/// Storage: appDir/models/minilm_l6_v2_quant.onnx
/// Not bundled in APK (keeps APK <150MB), optional download.
/// Fallback to TF-IDF if model missing (hybrid_retriever.dart hasOnnx flag).

class ModelDownloadService {
  static const String _modelFileName = 'minilm_l6_v2_quant.onnx';
  static const String _modelUrl = 'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx';
  // For testing, we can use a smaller dummy URL or local asset
  static const String _fallbackUrl = 'https://github.com/onnx/models/raw/main/text/machine_comprehension/tinybert/model.onnx';

  const ModelDownloadService();

  Future<Directory> _modelDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> get modelPath async {
    final dir = await _modelDir();
    return '${dir.path}/$_modelFileName';
  }

  Future<bool> isModelDownloaded() async {
    final path = await modelPath;
    final file = File(path);
    if (!await file.exists()) return false;
    final size = await file.length();
    return size > 1024 * 1024; // at least 1MB
  }

  Future<int> getModelSize() async {
    final path = await modelPath;
    final file = File(path);
    if (!await file.exists()) return 0;
    return await file.length();
  }

  /// Download model with progress callback (0..1) and cancel token
  Future<String?> downloadModel({
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
    bool useFallback = false,
  }) async {
    final url = useFallback ? _fallbackUrl : _modelUrl;
    final path = await modelPath;
    final dir = await _modelDir();

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    try {
      // Check if partial download exists for resume (range)
      int existing = 0;
      final file = File(path);
      if (await file.exists()) {
        existing = await file.length();
      }

      final options = Options(
        headers: existing > 0 ? {'Range': 'bytes=$existing-'} : null,
        responseType: ResponseType.bytes,
        followRedirects: true,
      );

      await dio.download(
        url,
        path,
        options: options,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            final progress = (existing + received) / (existing + total);
            onProgress(progress.clamp(0.0, 1.0));
          }
        },
        deleteOnError: false,
      );

      // Verify file size
      final size = await File(path).length();
      if (size < 1024 * 1024) {
        // Too small, likely failed
        await File(path).delete();
        return null;
      }

      return path;
    } catch (e) {
      // If failed and not resuming, try fallback URL
      if (!useFallback && e is DioException && e.type != DioExceptionType.cancel) {
        return downloadModel(onProgress: onProgress, cancelToken: cancelToken, useFallback: true);
      }
      return null;
    }
  }

  Future<void> deleteModel() async {
    final path = await modelPath;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Get model info for UI
  Future<Map<String, dynamic>> getModelInfo() async {
    final downloaded = await isModelDownloaded();
    final size = await getModelSize();
    return {
      'fileName': _modelFileName,
      'path': await modelPath,
      'downloaded': downloaded,
      'size': size,
      'sizeMb': (size / (1024 * 1024)).toStringAsFixed(2),
      'url': _modelUrl,
      'note': 'Optional 20MB download, not bundled in APK (keeps APK <150MB). Fallback to TF-IDF if missing.',
    };
  }
}
