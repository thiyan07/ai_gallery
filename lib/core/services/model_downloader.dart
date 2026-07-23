import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../logging/app_logger.dart';

/// Utility for downloading and managing ONNX models from Hugging Face Hub.
class ModelDownloader {
  ModelDownloader({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  /// Directory where models are stored.
  late final Directory _modelsDir;

  /// Initialize the model directory.
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    _modelsDir = Directory(path.join(appDir.path, 'models'));
    if (!await _modelsDir.exists()) {
      await _modelsDir.create(recursive: true);
      _logger.info('Created models directory: ${_modelsDir.path}');
    }
  }

  /// Get the local path for a model.
  String getModelPath(String modelId) {
    return path.join(_modelsDir.path, '$modelId.onnx');
  }

  /// Check if a model is downloaded.
  Future<bool> isModelDownloaded(String modelId) async {
    final file = File(getModelPath(modelId));
    return file.existsSync();
  }

  /// Download a model from Hugging Face Hub.
  ///
  /// [modelId] - Hugging Face model ID (e.g., "google/siglip-base-patch16-224")
  /// [filename] - Specific ONNX filename in the repo (e.g., "onnx/model.onnx")
  /// [revision] - Git revision/branch (default: "main")
  /// [progressCallback] - Called with progress (0.0 to 1.0)
  Future<String> downloadModel({
    required String modelId,
    required String filename,
    String revision = 'main',
    void Function(double)? progressCallback,
  }) async {
    final localPath = getModelPath(modelId.replaceAll('/', '_'));

    // Check if already exists
    if (await File(localPath).exists()) {
      _logger.info('Model already exists: $localPath');
      return localPath;
    }

    final url = 'https://huggingface.co/$modelId/resolve/$revision/$filename';
    _logger.info('Downloading model from: $url');

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException('Failed to download model: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final sink = File(localPath).openWrite();
      int downloaded = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0 && progressCallback != null) {
          progressCallback(downloaded / contentLength);
        }
      }

      await sink.close();
      await sink.flush();
      client.close();

      _logger.info('Model downloaded successfully: $localPath');
      return localPath;
    } catch (e, st) {
      _logger.error('Failed to download model', error: e, stackTrace: st);
      // Clean up partial download
      await File(localPath).delete();
      rethrow;
    }
  }

  /// Download a model from a direct URL.
  Future<String> downloadFromUrl({
    required String url,
    required String modelName,
    void Function(double)? progressCallback,
  }) async {
    final localPath = getModelPath(modelName);

    if (await File(localPath).exists()) {
      _logger.info('Model already exists: $localPath');
      return localPath;
    }

    _logger.info('Downloading model from: $url');

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException('Failed to download model: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final sink = File(localPath).openWrite();
      int downloaded = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0 && progressCallback != null) {
          progressCallback(downloaded / contentLength);
        }
      }

      await sink.close();
      await sink.flush();
      client.close();

      _logger.info('Model downloaded successfully: $localPath');
      return localPath;
    } catch (e, st) {
      _logger.error('Failed to download model', error: e, stackTrace: st);
      await File(localPath).delete();
      rethrow;
    }
  }

  /// List all downloaded models.
  Future<List<DownloadedModel>> listModels() async {
    if (!await _modelsDir.exists()) return [];

    final files = _modelsDir.listSync().whereType<File>();
    return files
        .where((f) => f.path.endsWith('.onnx'))
        .map((f) {
          final stat = f.statSync();
          return DownloadedModel(
            name: path.basenameWithoutExtension(f.path),
            path: f.path,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          );
        })
        .toList();
  }

  /// Delete a downloaded model.
  Future<void> deleteModel(String modelName) async {
    final file = File(getModelPath(modelName));
    if (await file.exists()) {
      await file.delete();
      _logger.info('Deleted model: $modelName');
    }
  }

  /// Get total size of all models.
  Future<int> getTotalSize() async {
    final models = await listModels();
    int total = 0;
    for (final model in models) {
      total += model.sizeBytes;
    }
    return total;
  }
}

/// Information about a downloaded model.
class DownloadedModel {
  const DownloadedModel({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Pre-configured model presets for common vision models.
class ModelPresets {
  static const Map<String, ModelConfig> presets = {
    'siglip-base-patch16-224': ModelConfig(
      modelId: 'google/siglip-base-patch16-224',
      filename: 'onnx/model.onnx',
      description: 'SigLIP Base Patch16 224 - Best quality image embeddings',
      inputSize: 224,
      embeddingDim: 768,
    ),
    'siglip-base-patch16-256': ModelConfig(
      modelId: 'google/siglip-base-patch16-256',
      filename: 'onnx/model.onnx',
      description: 'SigLIP Base Patch16 256 - Higher resolution',
      inputSize: 256,
      embeddingDim: 768,
    ),
    'clip-vit-base-patch32': ModelConfig(
      modelId: 'openai/clip-vit-base-patch32',
      filename: 'onnx/model.onnx',
      description: 'CLIP ViT-B/32 - Classic CLIP model',
      inputSize: 224,
      embeddingDim: 512,
    ),
    'mobileclip-s1': ModelConfig(
      modelId: 'apple/MobileCLIP_S1',
      filename: 'onnx/model.onnx',
      description: 'MobileCLIP S1 - Fast mobile-optimized',
      inputSize: 224,
      embeddingDim: 512,
    ),
    'mobileclip-s2': ModelConfig(
      modelId: 'apple/MobileCLIP_S2',
      filename: 'onnx/model.onnx',
      description: 'MobileCLIP S2 - Better quality mobile',
      inputSize: 224,
      embeddingDim: 512,
    ),
  };
}

/// Model configuration.
class ModelConfig {
  const ModelConfig({
    required this.modelId,
    required this.filename,
    required this.description,
    required this.inputSize,
    required this.embeddingDim,
  });

  final String modelId;
  final String filename;
  final String description;
  final int inputSize;
  final int embeddingDim;

  String get localName => modelId.replaceAll('/', '_');
}