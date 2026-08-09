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
  /// [localName] - Unique local filename (without .onnx) to avoid collisions when
  ///   multiple model files come from the same HF repo (e.g., image + text encoder)
  /// [revision] - Git revision/branch (default: "main")
  /// [progressCallback] - Called with progress (0.0 to 1.0)
  Future<String> downloadModel({
    required String modelId,
    required String filename,
    required String localName,
    String revision = 'main',
    void Function(double)? progressCallback,
  }) async {
    await _ensureInitialized();
    final localPath = await getModelPath(localName);

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
    String? localName,
    void Function(double)? progressCallback,
  }) async {
    await _ensureInitialized();
    final localPath = await getModelPath(localName ?? modelName);

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
      localName: 'siglip_base_patch16_224', // Matches bundled asset filename
    ),
    'siglip-base-patch16-224-text': ModelConfig(
      modelId: 'google/siglip-base-patch16-224',
      filename: 'onnx/text_model.onnx',
      description: 'SigLIP Base Patch16 224 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0, // N/A for text encoder
      embeddingDim: 768,
      localName: 'siglip_text_encoder', // Matches bundled asset filename
    ),
    'siglip-base-patch16-256': ModelConfig(
      modelId: 'google/siglip-base-patch16-256',
      filename: 'onnx/model.onnx',
      description: 'SigLIP Base Patch16 256 - Higher resolution',
      inputSize: 256,
      embeddingDim: 768,
      localName: 'siglip_base_patch16_256',
    ),
    'siglip-base-patch16-256-text': ModelConfig(
      modelId: 'google/siglip-base-patch16-256',
      filename: 'onnx/text_model.onnx',
      description: 'SigLIP Base Patch16 256 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0, // N/A for text encoder
      embeddingDim: 768,
      localName: 'siglip_text_encoder_256',
    ),
    'clip-vit-base-patch32': ModelConfig(
      modelId: 'openai/clip-vit-base-patch32',
      filename: 'onnx/model.onnx',
      description: 'CLIP ViT-B/32 - Classic CLIP model',
      inputSize: 224,
      embeddingDim: 512,
      localName: 'clip_vit_base_patch32',
    ),
    'clip-vit-base-patch32-text': ModelConfig(
      modelId: 'openai/clip-vit-base-patch32',
      filename: 'onnx/text_model.onnx',
      description: 'CLIP ViT-B/32 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0, // N/A for text encoder
      embeddingDim: 512,
      localName: 'clip_text_encoder',
    ),
    'mobileclip-s1': ModelConfig(
      modelId: 'apple/MobileCLIP_S1',
      filename: 'onnx/model.onnx',
      description: 'MobileCLIP S1 - Fast mobile-optimized',
      inputSize: 224,
      embeddingDim: 512,
      localName: 'mobileclip_s1',
    ),
    'mobileclip-s1-text': ModelConfig(
      modelId: 'apple/MobileCLIP_S1',
      filename: 'onnx/text_model.onnx',
      description: 'MobileCLIP S1 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0, // N/A for text encoder
      embeddingDim: 512,
      localName: 'mobileclip_s1_text_encoder',
    ),
    'mobileclip-s2': ModelConfig(
      modelId: 'apple/MobileCLIP_S2',
      filename: 'onnx/model.onnx',
      description: 'MobileCLIP S2 - Better quality mobile',
      inputSize: 224,
      embeddingDim: 512,
      localName: 'mobileclip_s2',
    ),
    'mobileclip-s2-text': ModelConfig(
      modelId: 'apple/MobileCLIP_S2',
      filename: 'onnx/text_model.onnx',
      description: 'MobileCLIP S2 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0, // N/A for text encoder
      embeddingDim: 512,
      localName: 'mobileclip_s2_text_encoder',
    ),

    // Object detection models (YOLOv8)
    'yolov8n': ModelConfig(
      modelId: 'onnx/community/yolov8n',
      filename: 'model.onnx',
      description: 'YOLOv8 Nano - Fastest, ~6MB',
      inputSize: 640,
      embeddingDim: 0, // Not applicable for detection
      localName: 'yolov8n',
    ),
    'yolov8s': ModelConfig(
      modelId: 'onnx/community/yolov8s',
      filename: 'model.onnx',
      description: 'YOLOv8 Small - Balanced, ~22MB',
      inputSize: 640,
      embeddingDim: 0,
      localName: 'yolov8s',
    ),
    'yolov8m': ModelConfig(
      modelId: 'onnx/community/yolov8m',
      filename: 'model.onnx',
      description: 'YOLOv8 Medium - Better accuracy, ~52MB',
      inputSize: 640,
      embeddingDim: 0,
      localName: 'yolov8m',
    ),
    'yolov8l': ModelConfig(
      modelId: 'onnx/community/yolov8l',
      filename: 'model.onnx',
      description: 'YOLOv8 Large - Best accuracy, ~87MB',
      inputSize: 640,
      embeddingDim: 0,
      localName: 'yolov8l',
    ),
    // Face detection models (BlazeFace)
    'blaze_face_short_range': ModelConfig(
      modelId: 'google/blazeface',
      filename: 'blaze_face_short_range.onnx',
      description: 'BlazeFace Short Range - Fast face detection 128x128, ~3MB',
      inputSize: 128,
      embeddingDim: 0,
      localName: 'blaze_face_short_range',
    ),
    'blaze_face_full_range': ModelConfig(
      modelId: 'google/blazeface',
      filename: 'blaze_face_full_range.onnx',
      description: 'BlazeFace Full Range - Better distance face detection 256x256, ~6MB',
      inputSize: 256,
      embeddingDim: 0,
      localName: 'blaze_face_full_range',
    ),
    // Face embedding models (for recognition/clustering)
    'mobilefacenet': ModelConfig(
      modelId: 'onnx/community/mobilefacenet',
      filename: 'model.onnx',
      description: 'MobileFaceNet - Fast face embedding 112x112, 128-dim, ~1.5MB',
      inputSize: 112,
      embeddingDim: 128,
      localName: 'mobilefacenet',
    ),
    'arcface_r18': ModelConfig(
      modelId: 'onnx/community/arcface_r18',
      filename: 'model.onnx',
      description: 'ArcFace ResNet18 - High quality face embedding 112x112, 512-dim, ~17MB',
      inputSize: 112,
      embeddingDim: 512,
      localName: 'arcface_r18',
    ),
    'arcface_r50': ModelConfig(
      modelId: 'onnx/community/arcface_r50',
      filename: 'model.onnx',
      description: 'ArcFace ResNet50 - Best quality face embedding 112x112, 512-dim, ~85MB',
      inputSize: 112,
      embeddingDim: 512,
      localName: 'arcface_r50',
    ),
    'adaface_ir18': ModelConfig(
      modelId: 'onnx/community/adaface_ir18',
      filename: 'model.onnx',
      description: 'AdaFace IR-18 - Robust face embedding 112x112, 512-dim, ~17MB',
      inputSize: 112,
      embeddingDim: 512,
      localName: 'adaface_ir18',
    ),
    // OCR models (PaddleOCR)
    'ppocr_det': ModelConfig(
      modelId: 'onnx/community/ppocr_det',
      filename: 'det_db.onnx',
      description: 'PaddleOCR DB Text Detector - 640x640, ~3MB',
      inputSize: 640,
      embeddingDim: 0,
      localName: 'ppocr_det',
    ),
    'ppocr_rec': ModelConfig(
      modelId: 'onnx/community/ppocr_rec',
      filename: 'rec_svtr.onnx',
      description: 'PaddleOCR SVTR Text Recognizer - 32x320, ~6MB',
      inputSize: 320,
      embeddingDim: 0,
      localName: 'ppocr_rec',
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
    this.localName,
  });

  final String modelId;
  final String filename;
  final String description;
  final int inputSize;
  final int embeddingDim;
  final String? localName;

  /// The local filename used for storage and asset lookup.
  /// Falls back to modelId with '/' replaced by '_' if not explicitly set.
  String get resolvedLocalName => localName ?? modelId.replaceAll('/', '_');
}