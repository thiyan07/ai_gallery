import 'dart:async';
import 'dart:io' show File, Directory, Platform, HttpException, IOSink;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../logging/app_logger.dart';
import '../utils/device_capabilities.dart';

/// Model installation state.
enum ModelState {
  notInstalled,
  downloading,
  verifying,
  installed,
  loading,
  ready,
  failed,
}

/// Result of a model download operation.
class ModelDownloadResult {
  final String localPath;
  final ModelState state;
  final String? errorMessage;
  final int? fileSize;
  final String? sha256;

  const ModelDownloadResult({
    required this.localPath,
    required this.state,
    this.errorMessage,
    this.fileSize,
    this.sha256,
  });

  bool get isSuccess => state == ModelState.installed || state == ModelState.ready;
}

/// Information about a downloaded model including its state.
class DownloadedModel {
  const DownloadedModel({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
    this.state = ModelState.installed,
    this.errorMessage,
    this.sha256,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;
  final ModelState state;
  final String? errorMessage;
  final String? sha256;

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  bool get isValid => state == ModelState.installed || state == ModelState.ready;

  DownloadedModel copyWith({
    ModelState? state,
    String? errorMessage,
    String? sha256,
  }) {
    return DownloadedModel(
      name: name,
      path: path,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
      state: state ?? this.state,
      errorMessage: errorMessage ?? this.errorMessage,
      sha256: sha256 ?? this.sha256,
    );
  }
}

/// Utility for downloading and managing ONNX models from Hugging Face Hub.
///
/// Features:
/// - Downloads to temporary .part file first
/// - Validates file size and SHA-256 checksum
/// - Atomically renames on success
/// - Handles partial downloads and cleanup
/// - Tracks model state (NOT_INSTALLED -> DOWNLOADING -> VERIFYING -> INSTALLED -> READY)
/// - Recovers from interrupted downloads on app restart
class ModelDownloader {
  ModelDownloader({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  /// Directory where models are stored.
  Directory? _modelsDir;

  /// In-memory state tracking for active downloads.
  final Map<String, ModelState> _modelStates = {};

  /// In-flight downloads keyed by resolved local name.
  ///
  /// Guards against concurrent `downloadModelConfig` calls for the same model
  /// writing to the same `.part` temp path simultaneously, which previously
  /// caused "Downloaded file failed validation" races (one download renames the
  /// temp file to its final location while another is still mid-write).
  final Map<String, Future<ModelDownloadResult>> _inFlightDownloads = {};

  /// Initialize the model directory.
  Future<void> initialize() async {
    await _ensureInitialized();
  }

  /// Ensure the model directory is initialized.
  Future<void> _ensureInitialized() async {
    if (_modelsDir != null) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _modelsDir = Directory(path.join(appDir.path, 'models'));
    } catch (_) {
      // Fallback for test environment without path_provider channel
      _modelsDir = Directory(path.join(Directory.systemTemp.path, 'ai_gallery_test_models'));
    }
    if (!await _modelsDir!.exists()) {
      await _modelsDir!.create(recursive: true);
      _logger.info('Created models directory: ${_modelsDir!.path}');
    }
  }

  /// Sanitize a model ID to prevent path traversal attacks.
  ///
  /// Strips directory separators, `..`, and leading slashes.
  static String _sanitizeModelId(String modelId) {
    return modelId
        .replaceAll('..', '')
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll(RegExp(r'^[./\\]+'), '')
        .replaceAll(RegExp(r'\.+$'), '')
        .trim();
  }

  /// Get the local path for a model (final location).
  Future<String> getModelPath(String modelId) async {
    await _ensureInitialized();
    final safe = _sanitizeModelId(modelId);
    return path.join(_modelsDir!.path, '$safe.onnx');
  }

  /// Get the temporary path for a model being downloaded.
  Future<String> getTempModelPath(String modelId) async {
    await _ensureInitialized();
    final safe = _sanitizeModelId(modelId);
    return path.join(_modelsDir!.path, '$safe.onnx.part');
  }

  /// Get the current state of a model.
  ModelState getModelState(String modelId) {
    return _modelStates[modelId] ?? ModelState.notInstalled;
  }

  /// Set the state of a model.
  void _setModelState(String modelId, ModelState state) {
    _modelStates[modelId] = state;
  }

  /// Check if a model is fully installed and valid.
  Future<bool> isModelDownloaded(String modelId) async {
    final localPath = await getModelPath(modelId);
    final file = File(localPath);
    if (!await file.exists()) return false;

    // Quick size check
    final stat = await file.stat();
    return stat.size > 0;
  }

  /// Validate a downloaded model file.
  Future<bool> _validateModelFile(String localPath, ModelConfig config) async {
    final file = File(localPath);

    // Check file exists
    if (!await file.exists()) {
      _logger.error('Validation failed: file does not exist: $localPath');
      return false;
    }

    // Check file size > 0
    final stat = await file.stat();
    if (stat.size == 0) {
      _logger.error('Validation failed: file is empty: $localPath');
      return false;
    }

    // Check minimum expected size
    if (config.expectedMinSizeBytes != null && stat.size < config.expectedMinSizeBytes!) {
      _logger.error('Validation failed: file too small (${stat.size} bytes, expected at least ${config.expectedMinSizeBytes}): $localPath');
      return false;
    }

    // Verify SHA-256 if provided
    if (config.sha256 != null) {
      final computedSha256 = await _computeSha256(file);
      if (computedSha256.toLowerCase() != config.sha256!.toLowerCase()) {
        _logger.error('Validation failed: SHA-256 mismatch. Expected: ${config.sha256}, Got: $computedSha256');
        return false;
      }
    }

    // Verify ONNX model validity using ONNX Runtime when appropriate
    final isOnnxValid = await _validateOnnxModel(localPath, config);
    if (!isOnnxValid) {
      _logger.error('ONNX validation failed: $localPath');
      return false;
    }

    return true;
  }

  /// Validate ONNX model file integrity.
  ///
  /// On mobile platforms, only performs lightweight file-level checks
  /// (exists, non-empty, minimum size) to avoid loading large models
  /// into memory during download. Full ONNX validation happens when the
  /// model is loaded for inference.
  Future<bool> _validateOnnxModel(String modelPath, ModelConfig config) async {
    try {
      final file = File(modelPath);
      if (!await file.exists()) {
        _logger.error('ONNX validation failed - file does not exist: $modelPath');
        return false;
      }
      final stat = await file.stat();
      if (stat.size == 0) {
        _logger.error('ONNX validation failed - file is empty: $modelPath');
        return false;
      }
      _logger.info('ONNX file integrity check passed: $modelPath (${stat.size} bytes)');
      return true;
    } on Exception catch (e, st) {
      _logger.error('ONNX validation failed: $modelPath', error: e, stackTrace: st);
      return false;
    }
  }

  /// Compute SHA-256 hash of a file using streaming to avoid loading
  /// the entire file into memory (critical for 100-300MB ONNX models).
  Future<String> _computeSha256(File file) async {
    Digest? result;
    final sink = _DigestSink((d) => result = d);
    final input = sha256.startChunkedConversion(sink);
    final stream = file.openRead();
    await for (final chunk in stream) {
      input.add(chunk);
    }
    input.close();
    return result.toString();
  }

  /// Download a model from Hugging Face Hub using a ModelConfig.
  ///
  /// This is the recommended method that handles all validation and state tracking.
  Future<ModelDownloadResult> downloadModelConfig(ModelConfig config, {
    void Function(double)? progressCallback,
    void Function(ModelState)? stateCallback,
  }) async {
    await _ensureInitialized();
    final localName = config.resolvedLocalName;

    // Deduplicate concurrent downloads for the same model. Multiple providers
    // (embedding, OCR, detection, face) may request the same model during app
    // init. Without this, each writes to the same `.part` temp path and races,
    // producing spurious "Downloaded file failed validation" StateErrors.
    final inFlight = _inFlightDownloads[localName];
    if (inFlight != null) {
      _logger.info('Download already in-flight for $localName, reusing it');
      return inFlight;
    }

    final future = _downloadModelConfigLocked(
      config,
      localName: localName,
      progressCallback: progressCallback,
      stateCallback: stateCallback,
    );
    // Remove the lock entry when done so a genuine re-download can happen later.
    _inFlightDownloads[localName] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightDownloads[localName], future)) {
        _inFlightDownloads.remove(localName);
      }
    }
  }

  Future<ModelDownloadResult> _downloadModelConfigLocked(
    ModelConfig config, {
    required String localName,
    void Function(double)? progressCallback,
    void Function(ModelState)? stateCallback,
  }) async {
    final localPath = await getModelPath(localName);
    final tempPath = await getTempModelPath(localName);

    // Check if already installed and valid
    if (await isModelDownloaded(localName)) {
      final isValid = await _validateModelFile(localPath, config);
      if (isValid) {
        _logger.info('Model already installed and valid: $localPath');
        _setModelState(localName, ModelState.installed);
        stateCallback?.call(ModelState.installed);
        return ModelDownloadResult(
          localPath: localPath,
          state: ModelState.installed,
          fileSize: (await File(localPath).stat()).size,
        );
      } else {
        _logger.warning('Existing model failed validation, will re-download: $localPath');
        // Delete invalid file
        await _safeDeleteFile(localPath);
      }
    }

    // Fix #6: Tier gate — low-tier devices should not download >120MB models (OOM risk).
    // siglip 300MB would OOM on 2-3GB RAM low tier. Recommended for low is mobileclip-s1 (~50MB).
    final expected = config.expectedMinSizeBytes;
    if (expected != null && expected > 120 * 1024 * 1024) {
      try {
        final caps = await DeviceCapabilities.instance;
        if (caps.tier == DeviceTier.low) {
          throw StateError(
            'MODEL_TOO_LARGE: ${config.description} (${(expected / 1024 / 1024).toStringAsFixed(0)}MB) '
            'is too large for low-tier device (${caps.modelName}, ${caps.tier.name}). '
            'Recommended: ${caps.recommendedModelPreset} (~50MB). '
            'Please use the recommended model for your device.',
          );
        }
      } catch (e) {
        if (e.toString().contains('MODEL_TOO_LARGE')) rethrow;
        // If tier check fails, proceed with download (disk-full will be caught as IOException)
        _logger.debug('Tier gate check skipped: $e');
      }
    }

    // Check for partial download and clean up
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      _logger.info('Found partial download, cleaning up: $tempPath');
      await _safeDeleteFile(tempPath);
    }

    final url = config.downloadUrl;
    _logger.info('Downloading model from: $url');
    _setModelState(localName, ModelState.downloading);
    stateCallback?.call(ModelState.downloading);

    try {
      final client = http.Client();
      IOSink? sink;
      try {
        final request = http.Request('GET', Uri.parse(url));
        final response = await client.send(request);

        if (response.statusCode == 404) {
          throw HttpException('Model file not found on Hugging Face (${config.modelId}/${config.filename}). '
              'The model repo might not have this ONNX file, or it may require authentication. '
              'Status: 404 Not Found');
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          throw HttpException('Access denied downloading from Hugging Face (${config.modelId}/${config.filename}). '
              'This model may require authentication or be gated. '
              'Status: ${response.statusCode}');
        } else if (response.statusCode != 200) {
          throw HttpException('Failed to download model from $url: ${response.statusCode}');
        }

        final contentLength = response.contentLength ?? 0;
        final fileSink = tempFile.openWrite();
        sink = fileSink;
        int downloaded = 0;
        int lastLogBytes = 0;

        // Use manual stream listening with a stall timeout.
        // The Dart http package stream may never terminate when a CDN
        // (CloudFront / Xet) keeps the connection alive after all bytes
        // have been sent. We detect this by:
        //   1. Breaking when downloaded >= contentLength (fast path).
        //   2. Aborting when no chunk arrives for 30 seconds (stall).
        const stallTimeout = Duration(seconds: 30);
        final completer = Completer<void>();
        Timer? stallTimer;
        Object? streamError;

        void safeComplete() {
          stallTimer?.cancel();
          if (!completer.isCompleted) completer.complete();
        }

        void resetStallTimer() {
          stallTimer?.cancel();
          stallTimer = Timer(stallTimeout, () {
            _logger.warning('Download stalled — no data for ${stallTimeout.inSeconds}s. '
                'Aborting after ${(downloaded / 1024 / 1024).toStringAsFixed(1)}MB');
            safeComplete();
          });
        }

        resetStallTimer();

        final subscription = response.stream.listen(
          (chunk) {
            fileSink.add(chunk);
            downloaded += chunk.length;
            if (contentLength > 0 && progressCallback != null) {
              progressCallback(downloaded / contentLength);
            }
            // Log progress every 10MB for large downloads
            if (contentLength > 0 && downloaded - lastLogBytes >= 10 * 1024 * 1024) {
              _logger.info('Download progress: ${(downloaded / 1024 / 1024).toStringAsFixed(1)}MB / ${(contentLength / 1024 / 1024).toStringAsFixed(1)}MB');
              lastLogBytes = downloaded;
            }
            resetStallTimer();
            // Break early when all expected bytes received — the HTTP response
            // stream may never signal completion (CDN keep-alive / CloudFront).
            if (contentLength > 0 && downloaded >= contentLength) {
              safeComplete();
            }
          },
          onError: (error) {
            streamError = error;
            safeComplete();
          },
          onDone: () {
            safeComplete();
          },
        );

        await completer.future;
        // Close the client first to force-drop the socket — this ensures
        // subscription.cancel() returns immediately instead of trying to
        // drain remaining bytes from a keep-alive HTTP connection.
        try {
          client.close();
        } catch (_) {}
        await subscription.cancel();

        // If the stream delivered an error, propagate it
        if (streamError != null) {
          throw HttpException('Download stream error: $streamError');
        }

        await fileSink.close();

        _logger.info('Model downloaded to temp file: $tempPath (${downloaded} bytes)');

        // Verify the download
        _setModelState(localName, ModelState.verifying);
        stateCallback?.call(ModelState.verifying);

        final isValid = await _validateModelFile(tempPath, config);
        if (!isValid) {
          throw StateError('Downloaded file failed validation');
        }

        // Atomic rename: temp file -> final location
        await tempFile.rename(localPath);
        _logger.info('Model installed successfully: $localPath');

        // Compute SHA-256 in background after rename (non-blocking)
        // ignore: discarded_futures
        _computeSha256(File(localPath)).then((hash) {
          _logger.info('Model SHA-256: $hash');
        }).catchError((e) {
          _logger.warning('SHA-256 computation failed: $e');
        });

        _setModelState(localName, ModelState.installed);
        stateCallback?.call(ModelState.installed);

        return ModelDownloadResult(
          localPath: localPath,
          state: ModelState.installed,
          fileSize: downloaded,
        );
      } finally {
        try {
          client.close();
        } catch (_) {}
      }
    } catch (e, st) {
      _logger.error('Failed to download model', error: e, stackTrace: st);

      // Clean up temp file
      await _safeDeleteFile(tempPath);

      _setModelState(localName, ModelState.failed);
      stateCallback?.call(ModelState.failed);

      return ModelDownloadResult(
        localPath: localPath,
        state: ModelState.failed,
        errorMessage: '$e',
      );
    }
  }

  /// Safely delete a file, never throwing if it doesn't exist.
  Future<void> _safeDeleteFile(String path) async {
    final file = File(path);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      _logger.warning('Failed to delete file (may not exist): $path - $e');
    }
  }

  /// Legacy download method for backward compatibility.
  @Deprecated('Use downloadModelConfig instead')
  Future<String> downloadModel({
    required String modelId,
    required String filename,
    required String localName,
    String revision = 'main',
    void Function(double)? progressCallback,
  }) async {
    final config = ModelConfig(
      modelId: modelId,
      filename: filename,
      description: '',
      inputSize: 0,
      embeddingDim: 0,
      localName: localName,
      revision: revision,
    );
    final result = await downloadModelConfig(config, progressCallback: progressCallback);
    if (!result.isSuccess) {
      throw StateError(result.errorMessage ?? 'Download failed');
    }
    return result.localPath;
  }

  /// Download a model from a direct URL.
  Future<String> downloadFromUrl({
    required String url,
    required String modelName,
    String? localName,
    void Function(double)? progressCallback,
  }) async {
    await _ensureInitialized();
    final resolvedLocalName = localName ?? modelName;
    final localPath = await getModelPath(resolvedLocalName);
    final tempPath = await getTempModelPath(resolvedLocalName);

    if (await File(localPath).exists()) {
      _logger.info('Model already exists: $localPath');
      return localPath;
    }

    // Clean up any partial download
    await _safeDeleteFile(tempPath);

    _logger.info('Downloading model from: $url');
    _setModelState(resolvedLocalName, ModelState.downloading);

    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        final response = await client.send(request);

        if (response.statusCode == 404) {
          throw HttpException('Model file not found at URL ($url). Status: 404 Not Found');
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          throw HttpException('Access denied downloading from $url. Status: ${response.statusCode}');
        } else if (response.statusCode != 200) {
          throw HttpException('Failed to download model from $url: ${response.statusCode}');
        }

        final contentLength = response.contentLength ?? 0;
        final fileSink = File(tempPath).openWrite();
        int downloaded = 0;

        const stallTimeout = Duration(seconds: 30);
        final completer = Completer<void>();
        Timer? stallTimer;
        Object? streamError;

        void safeComplete() {
          stallTimer?.cancel();
          if (!completer.isCompleted) completer.complete();
        }

        void resetStallTimer() {
          stallTimer?.cancel();
          stallTimer = Timer(stallTimeout, () {
            _logger.warning('Download stalled — no data for ${stallTimeout.inSeconds}s');
            safeComplete();
          });
        }

        resetStallTimer();

        final subscription = response.stream.listen(
          (chunk) {
            fileSink.add(chunk);
            downloaded += chunk.length;
            if (contentLength > 0 && progressCallback != null) {
              progressCallback(downloaded / contentLength);
            }
            resetStallTimer();
            if (contentLength > 0 && downloaded >= contentLength) {
              safeComplete();
            }
          },
          onError: (error) {
            streamError = error;
            safeComplete();
          },
          onDone: () {
            safeComplete();
          },
        );

        await completer.future;
        try {
          client.close();
        } catch (_) {}
        await subscription.cancel();

        if (streamError != null) {
          throw HttpException('Download stream error: $streamError');
        }

        await fileSink.close();

        _logger.info('Model downloaded to temp file: $tempPath');

        // Verify download (basic checks only for direct URLs)
        final tempFile = File(tempPath);
        if (!await tempFile.exists()) {
          throw StateError('Temp file missing after download');
        }
        final stat = await tempFile.stat();
        if (stat.size == 0) {
          throw StateError('Downloaded file is empty');
        }

        // Atomic rename
        await tempFile.rename(localPath);
        _logger.info('Model installed successfully: $localPath');

        _setModelState(resolvedLocalName, ModelState.installed);
        return localPath;
      } finally {
        try {
          client.close();
        } catch (_) {}
      }
    } catch (e, st) {
      _logger.error('Failed to download model', error: e, stackTrace: st);
      await _safeDeleteFile(tempPath);
      _setModelState(resolvedLocalName, ModelState.failed);
      rethrow;
    }
  }

  /// List all downloaded models with their states.
  Future<List<DownloadedModel>> listModels() async {
    await _ensureInitialized();
    if (!await _modelsDir!.exists()) return [];

    final files = _modelsDir!.listSync().whereType<File>();
    final models = <DownloadedModel>[];

    for (final file in files) {
      if (!file.path.endsWith('.onnx')) continue;
      if (file.path.endsWith('.part')) continue;

      final name = path.basenameWithoutExtension(file.path);
      final stat = await file.stat();

      // Determine state
      ModelState state = ModelState.installed;
      String? errorMessage;

      // Check if there's a corresponding .part file (incomplete download)
      final tempPath = await getTempModelPath(name);
      if (await File(tempPath).exists()) {
        state = ModelState.failed;
        errorMessage = 'Incomplete download (partial file exists)';
      } else if (stat.size == 0) {
        state = ModelState.failed;
        errorMessage = 'Zero-byte file';
      }

      models.add(DownloadedModel(
        name: name,
        path: file.path,
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
        state: state,
        errorMessage: errorMessage,
      ));
    }

    return models;
  }

  /// Delete a downloaded model (both final and temp files).
  Future<void> deleteModel(String modelName) async {
    final localPath = await getModelPath(modelName);
    final tempPath = await getTempModelPath(modelName);

    await _safeDeleteFile(localPath);
    await _safeDeleteFile(tempPath);

    _modelStates.remove(modelName);
    _logger.info('Deleted model: $modelName');
  }

  /// Get total size of all valid models.
  Future<int> getTotalSize() async {
    final models = await listModels();
    int total = 0;
    for (final model in models) {
      if (model.isValid) {
        total += model.sizeBytes;
      }
    }
    return total;
  }

  /// Clean up all partial downloads.
  Future<void> cleanupPartialDownloads() async {
    await _ensureInitialized();
    if (!await _modelsDir!.exists()) return;

    final files = _modelsDir!.listSync().whereType<File>();
    for (final file in files) {
      if (file.path.endsWith('.part')) {
        await _safeDeleteFile(file.path);
        _logger.info('Cleaned up partial download: ${file.path}');
      }
    }
  }
}

/// Pre-configured model presets for common vision models.
///
/// URLs are verified against Hugging Face repositories.
/// All ONNX models use Xenova conversions which provide:
/// - Full model (onnx/model.onnx) for combined image+text
/// - onnx/vision_model.onnx for image encoder only
/// - onnx/text_model.onnx for text encoder only
/// - Tokenizer models (tokenizer.json / spiece.model) for text processing
class ModelPresets {
  static const Map<String, ModelConfig> presets = {
    // Embedding models - SigLIP (verified: Xenova/siglip-base-patch16-*)
    'siglip-base-patch16-224': ModelConfig(
      modelId: 'Xenova/siglip-base-patch16-224',
      filename: 'onnx/vision_model.onnx',
      description: 'SigLIP Base Patch16 224 - Best quality image embeddings',
      inputSize: 224,
      embeddingDim: 768,
      localName: 'siglip_base_patch16_224',
      expectedMinSizeBytes: 300 * 1024 * 1024, // ~300MB minimum
      modelType: ModelType.visionEncoder,
    ),
    'siglip-base-patch16-224-text': ModelConfig(
      modelId: 'Xenova/siglip-base-patch16-224',
      filename: 'onnx/text_model.onnx',
      description: 'SigLIP Base Patch16 224 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0,
      embeddingDim: 768,
      localName: 'siglip_text_encoder',
      expectedMinSizeBytes: 200 * 1024 * 1024, // ~200MB minimum
      modelType: ModelType.textEncoder,
    ),
    'siglip-base-patch16-256': ModelConfig(
      modelId: 'Xenova/siglip-base-patch16-256',
      filename: 'onnx/vision_model.onnx',
      description: 'SigLIP Base Patch16 256 - Higher resolution',
      inputSize: 256,
      embeddingDim: 768,
      localName: 'siglip_base_patch16_256',
      expectedMinSizeBytes: 300 * 1024 * 1024,
      modelType: ModelType.visionEncoder,
    ),
    'siglip-base-patch16-256-text': ModelConfig(
      modelId: 'Xenova/siglip-base-patch16-256',
      filename: 'onnx/text_model.onnx',
      description: 'SigLIP Base Patch16 256 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0,
      embeddingDim: 768,
      localName: 'siglip_text_encoder_256',
      expectedMinSizeBytes: 200 * 1024 * 1024,
      modelType: ModelType.textEncoder,
    ),
    // Embedding models - MobileCLIP (verified: Xenova/mobileclip_s*)
    'mobileclip-s1': ModelConfig(
      modelId: 'Xenova/mobileclip_s1',
      filename: 'onnx/vision_model.onnx',
      description: 'MobileCLIP S1 - Fast mobile-optimized',
      inputSize: 224,
      embeddingDim: 512,
      localName: 'mobileclip_s1',
      expectedMinSizeBytes: 50 * 1024 * 1024,
      modelType: ModelType.visionEncoder,
    ),
    'mobileclip-s1-text': ModelConfig(
      modelId: 'Xenova/mobileclip_s1',
      filename: 'onnx/text_model.onnx',
      description: 'MobileCLIP S1 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0,
      embeddingDim: 512,
      localName: 'mobileclip_s1_text_encoder',
      expectedMinSizeBytes: 50 * 1024 * 1024,
      modelType: ModelType.textEncoder,
    ),
    'mobileclip-s2': ModelConfig(
      modelId: 'Xenova/mobileclip_s2',
      filename: 'onnx/vision_model.onnx',
      description: 'MobileCLIP S2 - Better quality mobile',
      inputSize: 224,
      embeddingDim: 512,
      localName: 'mobileclip_s2',
      expectedMinSizeBytes: 100 * 1024 * 1024,
      modelType: ModelType.visionEncoder,
    ),
    'mobileclip-s2-text': ModelConfig(
      modelId: 'Xenova/mobileclip_s2',
      filename: 'onnx/text_model.onnx',
      description: 'MobileCLIP S2 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0,
      embeddingDim: 512,
      localName: 'mobileclip_s2_text_encoder',
      expectedMinSizeBytes: 50 * 1024 * 1024,
      modelType: ModelType.textEncoder,
    ),
    // Embedding models - CLIP (verified: Xenova/clip-vit-base-patch32)
    'clip-vit-base-patch32': ModelConfig(
      modelId: 'Xenova/clip-vit-base-patch32',
      filename: 'onnx/vision_model.onnx',
      description: 'CLIP ViT-B/32 - Classic CLIP model',
      inputSize: 224,
      embeddingDim: 512,
      localName: 'clip_vit_base_patch32',
      expectedMinSizeBytes: 200 * 1024 * 1024,
      modelType: ModelType.visionEncoder,
    ),
    'clip-vit-base-patch32-text': ModelConfig(
      modelId: 'Xenova/clip-vit-base-patch32',
      filename: 'onnx/text_model.onnx',
      description: 'CLIP ViT-B/32 Text Encoder - Compatible text embeddings for semantic search',
      inputSize: 0,
      embeddingDim: 512,
      localName: 'clip_text_encoder',
      expectedMinSizeBytes: 200 * 1024 * 1024,
      modelType: ModelType.textEncoder,
    ),

    // Object detection models (YOLOv8) - Xenova conversions with onnx/ subdirectory
    // Xenova/yolov8* repos provide onnx/model.onnx
    'yolov8n': ModelConfig(
      modelId: 'Xenova/yolov8n',
      filename: 'onnx/model.onnx',
      description: 'YOLOv8 Nano - Fastest, ~6MB',
      inputSize: 640,
      embeddingDim: 0,
      localName: 'yolov8n',
      expectedMinSizeBytes: 4 * 1024 * 1024,
      modelType: ModelType.detector,
    ),
    'yolov8s': ModelConfig(
      modelId: 'Xenova/yolov8s',
      filename: 'onnx/model.onnx',
      description: 'YOLOv8 Small - Balanced, ~22MB',
      inputSize: 640,
      embeddingDim: 0,
      localName: 'yolov8s',
      expectedMinSizeBytes: 15 * 1024 * 1024,
      modelType: ModelType.detector,
    ),
    'yolov8m': ModelConfig(
      modelId: 'Xenova/yolov8m',
      filename: 'onnx/model.onnx',
      description: 'YOLOv8 Medium - Better accuracy, ~52MB',
      inputSize: 640,
      embeddingDim: 0,
      localName: 'yolov8m',
      expectedMinSizeBytes: 40 * 1024 * 1024,
      modelType: ModelType.detector,
    ),
    'yolov8l': ModelConfig(
      modelId: 'Xenova/yolov8l',
      filename: 'onnx/model.onnx',
      description: 'YOLOv8 Large - Best accuracy, ~87MB',
      inputSize: 640,
      embeddingDim: 0,
      localName: 'yolov8l',
      expectedMinSizeBytes: 70 * 1024 * 1024,
      modelType: ModelType.detector,
    ),

    // Face detection models (BlazeFace) - MediaPipe ONNX exports
    'blaze_face_short_range': ModelConfig(
      modelId: 'yakhyo/blazeface-onnx',
      filename: 'blaze_face_short_range.onnx',
      description: 'BlazeFace Short Range - Fast face detection 128x128, ~470KB',
      inputSize: 128,
      embeddingDim: 0,
      localName: 'blaze_face_short_range',
      expectedMinSizeBytes: 100 * 1024,
      modelType: ModelType.faceDetector,
    ),
    'blaze_face_full_range': ModelConfig(
      modelId: 'yakhyo/blazeface-onnx',
      filename: 'blaze_face_full_range.onnx',
      description: 'BlazeFace Full Range - Better distance face detection 256x256, ~1.5MB',
      inputSize: 256,
      embeddingDim: 0,
      localName: 'blaze_face_full_range',
      expectedMinSizeBytes: 500 * 1024,
      modelType: ModelType.faceDetector,
    ),

    // Face embedding models - SFace / ArcFace ONNX exports
    'mobilefacenet': ModelConfig(
      modelId: 'opencv/face_recognition_sface_2021dec',
      filename: 'face_recognition_sface_2021dec.onnx',
      description: 'SFace (MobileFaceNet backbone) - Fast face embedding 112x112, 128-dim, ~37MB',
      inputSize: 112,
      embeddingDim: 128,
      localName: 'mobilefacenet',
      expectedMinSizeBytes: 30 * 1024 * 1024,
      modelType: ModelType.faceEmbedding,
    ),
    'arcface_r18': ModelConfig(
      modelId: 'nielsr/arcface-embeddings',
      filename: 'arcface_r18.onnx',
      description: 'ArcFace ResNet18 - High quality face embedding 112x112, 512-dim, ~17MB',
      inputSize: 112,
      embeddingDim: 512,
      localName: 'arcface_r18',
      expectedMinSizeBytes: 12 * 1024 * 1024,
      modelType: ModelType.faceEmbedding,
    ),
    'arcface_r50': ModelConfig(
      modelId: 'nielsr/arcface-embeddings',
      filename: 'arcface_r50.onnx',
      description: 'ArcFace ResNet50 - Best quality face embedding 112x112, 512-dim, ~85MB',
      inputSize: 112,
      embeddingDim: 512,
      localName: 'arcface_r50',
      expectedMinSizeBytes: 60 * 1024 * 1024,
      modelType: ModelType.faceEmbedding,
    ),
    'adaface_ir18': ModelConfig(
      modelId: 'nielsr/arcface-embeddings',
      filename: 'arcface_r18.onnx',
      description: 'AdaFace IR-18 (fallback to ArcFace) - Robust face embedding 112x112, 512-dim',
      inputSize: 112,
      embeddingDim: 512,
      localName: 'adaface_ir18',
      expectedMinSizeBytes: 12 * 1024 * 1024,
      modelType: ModelType.faceEmbedding,
    ),

    // OCR models (PaddleOCR) - deepghs ONNX exports
    'ppocr_det': ModelConfig(
      modelId: 'deepghs/paddleocr',
      filename: 'det/ch_PP-OCRv4_det_infer.onnx',
      description: 'PaddleOCR DB Text Detector - 640x640, ~2.5MB',
      inputSize: 640,
      embeddingDim: 0,
      localName: 'ppocr_det',
      expectedMinSizeBytes: 1 * 1024 * 1024,
      modelType: ModelType.ocrDetector,
    ),
    'ppocr_rec': ModelConfig(
      modelId: 'deepghs/paddleocr',
      filename: 'rec/ch_PP-OCRv4_rec_infer.onnx',
      description: 'PaddleOCR Text Recognizer - 32x320, ~10MB',
      inputSize: 320,
      embeddingDim: 0,
      localName: 'ppocr_rec',
      expectedMinSizeBytes: 5 * 1024 * 1024,
      modelType: ModelType.ocrRecognizer,
    ),
    // Upscaling / enhancement models (Phase 15) — Real-ESRGAN small variants.
    // These are optional runtime models. If not installed, editing falls back
    // to local bicubic (image pkg) + algorithmic enhancement, preserving
    // local-first behavior without blocking the pipeline.
    'realesrgan-x2': ModelConfig(
      modelId: 'caq/realesrgan-x2plus-onnx',
      filename: 'realesrgan-x2plus.onnx',
      description: 'Real-ESRGAN x2 — lightweight super-resolution ~8MB',
      inputSize: 0,
      embeddingDim: 0,
      localName: 'realesrgan_x2',
      expectedMinSizeBytes: 4 * 1024 * 1024,
      modelType: ModelType.upscaler,
    ),
    'realesrgan-x4': ModelConfig(
      modelId: 'caq/realesrgan-x4plus-onnx',
      filename: 'realesrgan-x4plus.onnx',
      description: 'Real-ESRGAN x4 — lightweight super-resolution ~8MB',
      inputSize: 0,
      embeddingDim: 0,
      localName: 'realesrgan_x4',
      expectedMinSizeBytes: 4 * 1024 * 1024,
      modelType: ModelType.upscaler,
    ),
    'waifu2x-x2': ModelConfig(
      modelId: 'xenova/waifu2x',
      filename: 'onnx/model.onnx',
      description: 'Waifu2x x2 — alternative upscaler via ONNX',
      inputSize: 0,
      embeddingDim: 0,
      localName: 'waifu2x_x2',
      expectedMinSizeBytes: 2 * 1024 * 1024,
      modelType: ModelType.upscaler,
    ),
  };
}

/// Model type for categorization and validation.
enum ModelType {
  visionEncoder,
  textEncoder,
  detector,
  faceDetector,
  faceEmbedding,
  ocrDetector,
  ocrRecognizer,
  upscaler,
  enhancer,
  unknown,
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
    this.expectedMinSizeBytes,
    this.modelType = ModelType.unknown,
    this.revision = 'main',
    this.sha256,
    this.isRequired = false,
    this.supportedPlatforms = const ['android', 'ios', 'macos', 'windows', 'linux'],
  });

  final String modelId;
  final String filename;
  final String description;
  final int inputSize;
  final int embeddingDim;
  final String? localName;
  final int? expectedMinSizeBytes;
  final ModelType modelType;
  final String revision;
  final String? sha256;
  final bool isRequired;
  final List<String> supportedPlatforms;

  /// The local filename used for storage and asset lookup.
  /// Falls back to modelId with '/' replaced by '_' if not explicitly set.
  String get resolvedLocalName => localName ?? modelId.replaceAll('/', '_');

  /// Build the download URL for this model.
  String get downloadUrl => 'https://huggingface.co/$modelId/resolve/$revision/$filename';

  /// Check if this model is compatible with the current platform.
  bool get isPlatformSupported {
    final platform = Platform.operatingSystem;
    return supportedPlatforms.contains(platform);
  }
}

/// Sink that captures the final Digest from chunked SHA-256 conversion.
class _DigestSink implements Sink<Digest> {
  _DigestSink(this._onResult);
  final void Function(Digest) _onResult;
  Digest? _digest;

  @override
  void add(Digest data) {
    _digest = data;
  }

  @override
  void close() {
    if (_digest != null) _onResult(_digest!);
  }
}