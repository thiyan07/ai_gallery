import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/services/model_manager.dart';
import 'package:ai_gallery/core/utils/device_capabilities.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';

/// Local embedding provider using ONNX Runtime with SigLIP/CLIP/MobileCLIP models.
///
/// Automatically selects the optimal model based on device capabilities:
/// - Low-end: MobileCLIP-S1 (fastest, 512-dim)
/// - Mid-range: MobileCLIP-S2 (balanced, 512-dim)
/// - High-end: SigLIP Base Patch16-224 (best quality, 768-dim)
/// - Flagship: SigLIP Base Patch16-256 (highest quality, 768-dim)
///
/// Supports models from Hugging Face Hub via ModelManager or bundled assets.
class LocalEmbeddingProvider implements EmbeddingProvider {
  /// Create a provider with automatic model selection based on device capabilities.
  ///
  /// [logger] - Application logger.
  /// [modelManager] - Manages model downloading from Hugging Face.
  /// [modelAssetPath] - Optional bundled asset path for vision model fallback.
  /// [textModelAssetPath] - Optional bundled asset path for text encoder model.
  /// [tokenizerAssetPath] - Optional bundled asset path for tokenizer (SentencePiece).
  /// [modelPreset] - Optional explicit model preset (overrides auto-selection).
  /// [inputSize] - Input image size (determined by model if null).
  /// [forceTier] - Optional forced device tier for testing.
  LocalEmbeddingProvider({
    required AppLogger logger,
    required ModelManager modelManager,
    String? modelAssetPath,
    String? textModelAssetPath,
    String? tokenizerAssetPath,
    String? modelPreset,
    int? inputSize,
    DeviceTier? forceTier,
  })  : _logger = logger,
        _modelManager = modelManager,
        _modelAssetPath = modelAssetPath ?? 'assets/models/siglip_base_patch16_224.onnx',
        _textModelAssetPath = textModelAssetPath ?? 'assets/models/siglip_text_encoder.onnx',
        _tokenizerAssetPath = tokenizerAssetPath ?? 'assets/models/siglip_tokenizer.model',
        _forcedPreset = modelPreset,
        _forcedTier = forceTier,
        _inputSize = inputSize;

  final AppLogger _logger;
  final ModelManager _modelManager;
  final String _modelAssetPath;
  final String _textModelAssetPath;
  final String _tokenizerAssetPath;
  final String? _forcedPreset;
  final DeviceTier? _forcedTier;
  final int? _inputSize;

  OrtSession? _visionSession;
  OrtSession? _textSession;
  bool _initialized = false;
  DeviceCapabilities? _capabilities;
  String? _resolvedPreset;
  int? _resolvedInputSize;

  // ImageNet normalization constants
  static const _mean = [0.485, 0.456, 0.406];
  static const _std = [0.229, 0.224, 0.225];

  // Tokenizer - simple word-piece/Drop-in for CLIP/SigLIP
  int _vocabSize = 0;

  /// Get the currently active model preset.
  String get modelPreset => _resolvedPreset ?? _determinePreset();

  /// Get the current device capabilities (after initialization).
  DeviceCapabilities? get capabilities => _capabilities;

  /// Get the resolved input size for the current model.
  int get inputSize => _resolvedInputSize ?? _determineInputSize();

  @override
  String get id => 'local_$modelPreset';

  @override
  String get name => 'Auto: $modelPreset (ONNX)';

  @override
  Future<bool> get isAvailable async {
    try {
      await _ensureInitialized();
      return _visionSession != null && _textSession != null;
    } catch (e) {
      _logger.warning('Local embedding provider not available: $e');
      return false;
    }
  }

  /// Initialize the ONNX Runtime sessions with auto-selected model.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    try {
      // Detect device capabilities and select model
      _capabilities = await DeviceCapabilities.instance;
      _resolvedPreset = _determinePreset();
      _resolvedInputSize = _determineInputSize();

      // Use ! since _capabilities is guaranteed non-null after the await above
      final caps = _capabilities!;
      _logger.info(
        'Device: ${caps.modelName} (${caps.tier.name}) '
        '→ Model: $_resolvedPreset (${_resolvedInputSize}px, '
        '${caps.performanceMultiplier.toStringAsFixed(1)}x perf)',
      );

      // Select model in ModelManager (triggers download if needed)
      _modelManager.selectModel(_resolvedPreset!);

      // Try to get model path from ModelManager (downloads if needed)
      String? modelPath;
      try {
        modelPath = await _modelManager.getSelectedModelPath();
      } catch (e) {
        _logger.warning('ModelManager not initialized, falling back to assets: $e');
      }

      Uint8List visionModelBytes;

      if (modelPath != null) {
        // Load from downloaded model file
        _logger.info('Loading ONNX vision model from: $modelPath');
        final file = File(modelPath);
        visionModelBytes = await file.readAsBytes();
      } else {
        // Fallback to bundled asset
        _logger.info('Loading ONNX vision model from assets: $_modelAssetPath');
        visionModelBytes = await _loadModelFromAssets(_modelAssetPath);
      }

      // Load text encoder model
      Uint8List? textModelBytes;
      try {
        String? textModelPath;
        // Try to get text encoder from ModelManager
        try {
          textModelPath = await _modelManager.getSelectedModelPath();
          // This might not work for text encoder, so try asset fallback
        } catch (_) {}

        if (textModelPath != null && await File(textModelPath).exists()) {
          _logger.info('Loading ONNX text encoder from: $textModelPath');
          textModelBytes = await File(textModelPath).readAsBytes();
        } else {
          _logger.info('Loading ONNX text encoder from assets: $_textModelAssetPath');
          textModelBytes = await _loadModelFromAssets(_textModelAssetPath);
        }
      } catch (e) {
        _logger.warning('Text encoder not available, text search will use fallback: $e');
        textModelBytes = null;
      }

      // Load tokenizer
      await _loadTokenizer();

      // Configure ONNX session options based on device capabilities
      final sessionOptions = OrtSessionOptions()
        ..setIntraOpNumThreads(_getOptimalThreadCount())
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      // Add CPU provider with appropriate flags
      if (caps.hasNpu && caps.useGpuDelegate) {
        // Note: ONNX Runtime Android supports NNAPI via CPU provider flags
        // For explicit NNAPI delegate, additional setup is needed
        sessionOptions.appendCPUProvider(CPUFlags.useArena);
      } else {
        sessionOptions.appendCPUProvider(CPUFlags.useArena);
      }

      // Create ONNX vision session
      _visionSession = OrtSession.fromBuffer(visionModelBytes, sessionOptions);

      // Create ONNX text session if model is available
      if (textModelBytes != null) {
        _textSession = OrtSession.fromBuffer(textModelBytes, sessionOptions);
        _logger.info('Text encoder ONNX session created successfully');
      } else {
        _logger.warning('Text encoder not loaded - text search will use fallback');
      }

      _initialized = true;
      _logger.info('LocalEmbeddingProvider initialized with model: $_resolvedPreset');
    } catch (e, st) {
      _logger.error(
        'Failed to initialize LocalEmbeddingProvider',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Determine the model preset to use.
  String _determinePreset() {
    if (_forcedPreset != null) return _forcedPreset;
    if (_forcedTier != null) return _presetForTier(_forcedTier);
    return _capabilities?.recommendedModelPreset ?? 'siglip-base-patch16-224';
  }

  /// Determine input size for the current model.
  int _determineInputSize() {
    if (_inputSize != null) return _inputSize;
    final preset = _determinePreset();
    return switch (preset) {
      'siglip-base-patch16-256' => 256,
      _ => 224,
    };
  }

  /// Get model preset for a specific tier.
  String _presetForTier(DeviceTier tier) {
    return switch (tier) {
      DeviceTier.low => 'mobileclip-s1',
      DeviceTier.medium => 'mobileclip-s2',
      DeviceTier.high => 'siglip-base-patch16-224',
      DeviceTier.flagship => 'siglip-base-patch16-256',
    };
  }

  /// Get optimal thread count for ONNX inference based on device.
  int _getOptimalThreadCount() {
    if (_capabilities == null) return 4;
    final cores = _capabilities!.cpuCores;
    // Leave 1-2 cores for OS/UI, use rest for inference
    return cores <= 2 ? 1 : cores - 1;
  }

  /// Load model bytes from Flutter assets.
  Future<Uint8List> _loadModelFromAssets(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List();
    } catch (e) {
      throw StateError(
        'Failed to load ONNX model from assets at "$assetPath". '
        'Please add a SigLIP/CLIP ONNX model to assets/models/ and update pubspec.yaml, '
        'or ensure ModelManager can download ${_determinePreset()} from Hugging Face. '
        'Error: $e',
      );
    }
  }

  /// Load tokenizer from SentencePiece model file.
  Future<void> _loadTokenizer() async {
    try {
      await rootBundle.load(_tokenizerAssetPath);
      // For now, use a simple word-level tokenizer as fallback
      // In production, integrate proper SentencePiece decoding
      _vocabSize = 32000; // Default CLIP/SigLIP vocab size
      _logger.info('Tokenizer loaded (placeholder implementation)');
    } catch (e) {
      _logger.warning('Failed to load tokenizer, using fallback: $e');
      _vocabSize = 32000;
    }
  }

  /// Simple tokenizer for CLIP/SigLIP - converts text to token IDs.
  /// This is a simplified version; production should use proper SentencePiece.
  List<int> _tokenize(String text) {
    // Split by whitespace and simple punctuation, map to vocab indices
    // This is a placeholder - real implementation needs SentencePiece
    final words = text.toLowerCase().split(RegExp(r'[\s\p{P}]+')).where((w) => w.isNotEmpty).toList();
    return words.map((w) => w.hashCode.abs() % _vocabSize).toList();
  }

  @override
  Future<Float32List> generateEmbedding(Uint8List imageBytes) async {
    await _ensureInitialized();

    if (_visionSession == null) {
      throw StateError('ONNX vision session not initialized');
    }

    try {
      // Preprocess image: decode, resize, normalize, convert to tensor
      final inputTensor = _preprocessImage(imageBytes);

      // Run inference
      final outputs = _visionSession!.run(
        OrtRunOptions(),
        {
          _visionSession!.inputNames.first: inputTensor,
        },
      );

      // Get first output tensor
      final outputTensor = outputs.first;
      if (outputTensor == null) {
        throw StateError('No output tensor from vision model');
      }

      // Extract embedding as Float32List
      final dynamic outputValue = outputTensor.value;
      Float32List embedding;
      if (outputValue is List<double>) {
        embedding = Float32List.fromList(outputValue);
      } else if (outputValue is Float32List) {
        embedding = outputValue;
      } else {
        throw StateError('Unexpected output tensor type: ${outputValue.runtimeType}');
      }

      // L2 normalize
      final normalized = _l2Normalize(embedding);

      return Float32List.fromList(normalized);
    } catch (e, st) {
      _logger.error('Failed to generate image embedding', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<Float32List> generateTextEmbedding(String text) async {
    await _ensureInitialized();

    if (_textSession == null) {
      _logger.warning(
        'Text encoder not available, using fallback embedding. '
        'Add a text encoder ONNX model for production.',
      );
      // Fallback: deterministic pseudo-embedding from text hash
      return _fallbackTextEmbedding(text);
    }

    try {
      // Tokenize text
      final tokens = _tokenize(text);

      // Pad or truncate to max sequence length (77 for CLIP/SigLIP)
      const maxLength = 77;
      final inputIds = List<int>.filled(maxLength, 0);
      for (int i = 0; i < tokens.length && i < maxLength - 2; i++) {
        inputIds[i + 1] = tokens[i]; // +1 for BOS token at position 0
      }
      inputIds[0] = 49406; // BOS token (CLIP default)
      if (tokens.length < maxLength - 1) {
        inputIds[tokens.length + 1] = 49407; // EOS token
      }

      // Create input tensor [1, 77]
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        Int32List.fromList(inputIds),
        [1, maxLength],
      );

      // Run text encoder inference
      final outputs = _textSession!.run(
        OrtRunOptions(),
        {
          _textSession!.inputNames.first: inputTensor,
        },
      );

      // Get output tensor
      final outputTensor = outputs.first;
      if (outputTensor == null) {
        throw StateError('No output tensor from text encoder');
      }

      // Extract embedding and normalize
      final dynamic outputValue = outputTensor.value;
      Float32List embedding;
      if (outputValue is List<double>) {
        embedding = Float32List.fromList(outputValue);
      } else if (outputValue is Float32List) {
        embedding = outputValue;
      } else {
        throw StateError('Unexpected output tensor type: ${outputValue.runtimeType}');
      }

      // L2 normalize
      final normalized = _l2Normalize(embedding);

      _logger.info('Generated text embedding for: "$text" (dim: ${normalized.length})');
      return Float32List.fromList(normalized);
    } catch (e, st) {
      _logger.error('Failed to generate text embedding, using fallback', error: e, stackTrace: st);
      return _fallbackTextEmbedding(text);
    }
  }

  /// Fallback text embedding using hash-based deterministic generation.
  Float32List _fallbackTextEmbedding(String text) {
    final hash = _hashText(text);
    final dim = _getEmbeddingDimension();
    final random = List.generate(dim, (i) => sin((hash + i) * 0.123456));
    final normalized = _l2Normalize(Float32List.fromList(random));
    return Float32List.fromList(normalized);
  }

  /// Get embedding dimension for current model.
  int _getEmbeddingDimension() {
    final preset = _determinePreset();
    return switch (preset) {
      'siglip-base-patch16-224' || 'siglip-base-patch16-256' => 768,
      _ => 512, // CLIP and MobileCLIP variants
    };
  }

  /// Simple string hash for deterministic pseudo-embedding.
  int _hashText(String text) {
    int hash = 0;
    for (final codeUnit in text.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// Preprocess image bytes to model input tensor [1, 3, H, W].
  ///
  /// Steps:
  /// 1. Decode image using `image` package
  /// 2. Resize to inputSize x inputSize (maintaining aspect ratio with center crop)
  /// 3. Normalize to ImageNet mean/std
  /// 4. Convert to NCHW format [1, 3, H, W]
  OrtValueTensor _preprocessImage(Uint8List imageBytes) {
    try {
      // Decode image
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        throw StateError('Failed to decode image bytes');
      }

      final size = inputSize;

      // Resize and center crop to inputSize x inputSize
      img.Image resizedImage;
      if (decodedImage.width != decodedImage.height) {
        // Resize shorter side to inputSize, then center crop
        if (decodedImage.width < decodedImage.height) {
          resizedImage = img.copyResize(decodedImage, width: size);
          final yOffset = (resizedImage.height - size) ~/ 2;
          resizedImage = img.copyCrop(
            resizedImage,
            x: 0,
            y: yOffset,
            width: size,
            height: size,
          );
        } else {
          resizedImage = img.copyResize(decodedImage, height: size);
          final xOffset = (resizedImage.width - size) ~/ 2;
          resizedImage = img.copyCrop(
            resizedImage,
            x: xOffset,
            y: 0,
            width: size,
            height: size,
          );
        }
      } else {
        resizedImage = img.copyResize(
          decodedImage,
          width: size,
          height: size,
        );
      }

      // Convert to RGB and normalize
      final input = Float32List(3 * size * size);
      // Use toUint8List() to get raw RGBA bytes
      final pixelData = resizedImage.toUint8List();

      for (int c = 0; c < 3; c++) {
        for (int h = 0; h < size; h++) {
          for (int w = 0; w < size; w++) {
            final pixelIndex = (h * size + w) * 4 + c; // RGBA format
            final value = pixelData[pixelIndex] / 255.0;
            input[(c * size * size) + (h * size) + w] = (value - _mean[c]) / _std[c];
          }
        }
      }

      return OrtValueTensor.createTensorWithDataList(input, [1, 3, size, size]);
    } catch (e, st) {
      _logger.error('Image preprocessing failed', error: e, stackTrace: st);
      // Return dummy tensor as fallback (will produce meaningless embedding)
      final dummyData = Float32List(3 * inputSize * inputSize);
      return OrtValueTensor.createTensorWithDataList(dummyData, [1, 3, inputSize, inputSize]);
    }
  }

  /// L2 normalize a vector.
  List<double> _l2Normalize(Float32List vector) {
    double norm = 0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = norm <= 0 ? 1.0 : sqrt(norm);
    return vector.map((v) => v / norm).toList();
  }

  @override
  Future<void> initialize() async {
    await _ensureInitialized();
  }

  @override
  Future<void> warmUp() async {
    await _ensureInitialized();
    if (_visionSession == null) return;

    try {
      final dummyData = Float32List(3 * inputSize * inputSize);
      final tensor = OrtValueTensor.createTensorWithDataList(dummyData, [1, 3, inputSize, inputSize]);
      _visionSession!.run(
        OrtRunOptions(),
        {_visionSession!.inputNames.first: tensor},
      );
      _logger.info('Local embedding model warmed up');
    } catch (e) {
      _logger.warning('Local embedding warm-up failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    _visionSession?.release();
    _textSession?.release();
    _initialized = false;
  }

  @override
  Future<Float32List> generateEmbeddingFromFace({
    required Uint8List imageBytes,
    required FaceDetection faceDetection,
  }) async {
    // Local embedding provider doesn't support face alignment; fall back to general image embedding
    return generateEmbedding(imageBytes);
  }
}