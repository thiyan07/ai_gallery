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
  Directory? _modelsDir;

  /// Initialize the model directory.
  Future<void> initialize() async {
    await _ensureInitialized();
  }

  /// Ensure the model directory is initialized.
  Future<void> _ensureInitialized() async {
    if (_modelsDir != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    _modelsDir = Directory(path.join(appDir.path, 'models'));
    if (!await _modelsDir!.exists()) {
      await _modelsDir!.create(recursive: true);
      _logger.info('Created models directory: ${_modelsDir!.path}');
    }
  }

  /// Get the local path for a model.
  Future<String> getModelPath(String modelId) async {
    await _ensureInitialized();
    return path.join(_modelsDir!.path, '$modelId.onnx');
  }

  /// Check if a model is downloaded.
  Future<bool> isModelDownloaded(String modelId) async {
    final localPath = await getModelPath(modelId);
    final file = File(localPath);
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
    await _ensureInitialized();
    final localPath = await getModelPath(modelId.replaceAll('/', '_'));

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
    await _ensureInitialized();
    final localPath = await getModelPath(modelName);

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
    await _ensureInitialized();
    if (!await _modelsDir!.exists()) return [];

    final files = _modelsDir!.listSync().whereType<File>();
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
    final localPath = await getModelPath(modelName);
    final file = File(localPath);
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
    // Embedding models
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

    // Object detection models (YOLOv8)
    'yolov8n': ModelConfig(
      modelId: 'onnx/community/yolov8n',
      filename: 'model.onnx',
      description: 'YOLOv8 Nano - Fastest, ~6MB',
      inputSize: 640,
      embeddingDim: 0, // Not applicable for detection
    ),
    'yolov8s': ModelConfig(
      modelId: 'onnx/community/yolov8s',
      filename: 'model.onnx',
      description: 'YOLOv8 Small - Balanced, ~22MB',
      inputSize: 640,
      embeddingDim: 0,
    ),
    'yolov8m': ModelConfig(
      modelId: 'onnx/community/yolov8m',
      filename: 'model.onnx',
      description: 'YOLOv8 Medium - Better accuracy, ~52MB',
      inputSize: 640,
      embeddingDim: 0,
    ),
    'yolov8l': ModelConfig(
      modelId: 'onnx/community/yolov8l',
      filename: 'model.onnx',
      description: 'YOLOv8 Large - Best accuracy, ~87MB',
      inputSize: 640,
      embeddingDim: 0,
    ),
    'yolov8x': ModelConfig(
      modelId: 'onnx/community/yolov8x',
      filename: 'model.onnx',
      description: 'YOLOv8 Extra Large - Maximum accuracy, ~136MB',
      inputSize: 640,
      embeddingDim: 0,
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