import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../../core/logging/app_logger.dart';
import '../../core/services/model_manager.dart';
import '../../core/utils/device_capabilities.dart';
import '../../domain/models/embedding.dart';
import '../../domain/models/face_detection.dart';
import 'embedding_provider.dart';

/// Local face embedding using ONNX Runtime with ArcFace/MobileFaceNet models.
///
/// Face embeddings are used for face recognition and clustering (grouping photos of the same person).
///
/// Models available:
/// - mobilefacenet: 112x112 input, fast mobile-optimized, ~1.5MB, 128-dim embeddings
/// - arcface_r18: ResNet18-based ArcFace, 112x112 input, ~17MB, 512-dim embeddings
/// - arcface_r50: ResNet50-based ArcFace, 112x112 input, ~85MB, 512-dim embeddings
/// - adaface_ir18: IR-18 based AdaFace, 112x112 input, ~17MB, 512-dim embeddings
class FaceEmbeddingProvider implements EmbeddingProvider {
  /// Create a face embedding provider.
  ///
  /// [logger] - Application logger.
  /// [modelManager] - Manages model downloading from Hugging Face.
  /// [modelAssetPath] - Optional bundled asset path for fallback.
  /// [modelVariant] - Model variant: 'mobilefacenet', 'arcface_r18', 'arcface_r50', 'adaface_ir18'.
  /// [inputSize] - Input image size (default 112 for face recognition models).
  FaceEmbeddingProvider({
    required AppLogger logger,
    required ModelManager modelManager,
    String? modelAssetPath,
    String modelVariant = 'mobilefacenet',
    int? inputSize,
  })  : _logger = logger,
        _modelManager = modelManager,
        _modelAssetPath = modelAssetPath ?? 'assets/models/mobilefacenet.onnx',
        _modelVariant = modelVariant,
        _inputSize = inputSize ?? 112;

  final AppLogger _logger;
  final ModelManager _modelManager;
  final String _modelAssetPath;
  final String _modelVariant;
  final int _inputSize;

  OrtSession? _session;
  bool _initialized = false;
  int _embeddingDim = 128;
  DeviceCapabilities? _capabilities;

  @override
  String get id => 'face_$_modelVariant';

  @override
  String get name => 'Face Embedding (ONNX): $_modelVariant';

  @override
  Future<bool> get isAvailable async {
    try {
      await _ensureInitialized();
      return _session != null;
    } catch (e) {
      _logger.warning('Face embedding provider not available: $e');
      return false;
    }
  }

  /// Initialize the ONNX Runtime session with face embedding model.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    try {
      // Detect device capabilities and select model
      _capabilities = await DeviceCapabilities.instance;
      _embeddingDim = _determineEmbeddingDim();

      final caps = _capabilities!;
      _logger.info(
        'Device: ${caps.modelName} (${caps.tier.name}) '
        '→ Face Embedding Model: $_modelVariant (${_inputSize}px, $_embeddingDim-dim, '
        '${caps.performanceMultiplier.toStringAsFixed(1)}x perf)',
      );

      // Select model in ModelManager (triggers download if needed)
      _modelManager.selectModel(_modelVariant);

      // Try to get model path from ModelManager (downloads if needed with validation)
      ModelDownloadResult? result;
      try {
        result = await _modelManager.getSelectedModelPath();
      } catch (e) {
        _logger.warning('ModelManager not ready, falling back to assets: $e');
      }

      Uint8List modelBytes;

      if (result != null && result.isSuccess && result.localPath.isNotEmpty) {
        // Load from downloaded model file
        _logger.info('Loading face embedding model from: ${result.localPath}');
        final file = File(result.localPath);
        modelBytes = await file.readAsBytes();
      } else {
        // Fallback to bundled asset
        _logger.info('Loading face embedding model from assets: $_modelAssetPath');
        modelBytes = await _loadModelFromAssets();
      }

      // Configure ONNX session options
      final sessionOptions = OrtSessionOptions()
        ..setIntraOpNumThreads(_getOptimalThreadCount())
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      // Add CPU provider
      sessionOptions.appendCPUProvider(CPUFlags.useArena);

      // Create ONNX session
      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _initialized = true;
      _logger.info('FaceEmbeddingProvider initialized with model: $_modelVariant (${_embeddingDim}D)');
    } catch (e, st) {
      _logger.error(
        'Failed to initialize FaceEmbeddingProvider',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Determine embedding dimension for the current model.
  int _determineEmbeddingDim() {
    return switch (_modelVariant) {
      'mobilefacenet' => 128,
      'arcface_r18' => 512,
      'arcface_r50' => 512,
      'adaface_ir18' => 512,
      _ => 128,
    };
  }

  /// Get optimal thread count for ONNX inference.
  int _getOptimalThreadCount() {
    if (_capabilities == null) return 2;
    final cores = _capabilities!.cpuCores;
    return cores <= 2 ? 1 : min(cores, 4);
  }

  /// Load model bytes from Flutter assets.
  Future<Uint8List> _loadModelFromAssets() async {
    try {
      final data = await rootBundle.load(_modelAssetPath);
      return data.buffer.asUint8List();
    } catch (e) {
      _logger.error('Failed to load model from assets: $e');
      rethrow;
    }
  }

  @override
  Future<Float32List> generateEmbedding(Uint8List imageBytes) async {
    await _ensureInitialized();

    if (_session == null) {
      throw StateError('ONNX session not initialized');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Decode image to get dimensions
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        throw StateError('Failed to decode image');
      }

      // Preprocess: resize to input size, normalize, convert to NCHW tensor
      final inputTensor = _preprocessImage(imageBytes);

      // Run inference
      final outputs = _session!.run(
        OrtRunOptions(),
        {_session!.inputNames.first: inputTensor},
      );

      stopwatch.stop();

      // Parse output: [1, embedding_dim]
      final outputTensor = outputs[0] as OrtValueTensor?;

      if (outputTensor == null) {
        throw StateError('No output tensor from model');
      }

      final outputValue = outputTensor.value;
      if (outputValue is! Float32List) {
        throw StateError('Unexpected output tensor type: ${outputValue.runtimeType}');
      }

      final embedding = Float32List.fromList(outputValue);

      // L2 normalize the embedding
      final normalized = _l2Normalize(embedding);

      _logger.debug('Face embedding generated (${normalized.length}D) in ${stopwatch.elapsedMilliseconds}ms');

      return normalized;
    } catch (e, st) {
      _logger.error('Failed to generate face embedding', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Preprocess face crop for face embedding input: [1, 3, H, W] NCHW format.
  ///
  /// Face recognition models typically expect:
  /// - Input: 112x112 RGB
  /// - Normalization: mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5] (to [-1, 1])
  ///   OR mean=[0, 0, 0], std=[1, 1, 1] (to [0, 1])
  OrtValueTensor _preprocessImage(Uint8List imageBytes) {
    final decodedImage = img.decodeImage(imageBytes)!;

    // Resize to input size (face recognition models use 112x112)
    final resized = img.copyResize(
      decodedImage,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Convert to normalized [-1, 1] NCHW tensor [1, 3, H, W]
    // Most face recognition models (ArcFace, MobileFaceNet, AdaFace) use this normalization
    final inputData = Float32List(1 * 3 * _inputSize * _inputSize);
    var idx = 0;

    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _inputSize; y++) {
        for (var x = 0; x < _inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          final value = (c == 0 ? pixel.r : c == 1 ? pixel.g : pixel.b) / 127.5 - 1.0;
          inputData[idx++] = value;
        }
      }
    }

    return OrtValueTensor.createTensorWithDataList(inputData, [1, 3, _inputSize, _inputSize]);
  }

  /// L2 normalize a vector.
  Float32List _l2Normalize(Float32List vector) {
    double norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm == 0) return vector;

    final result = Float32List(vector.length);
    for (var i = 0; i < vector.length; i++) {
      result[i] = vector[i] / norm;
    }
    return result;
  }

  @override
  Future<Float32List> generateTextEmbedding(String text) async {
    // Face embedding provider doesn't support text embeddings
    // Return a deterministic fallback
    return _fallbackTextEmbedding(text);
  }

  Float32List _fallbackTextEmbedding(String text) {
    final hash = text.hashCode;
    final dim = _embeddingDim;
    final random = List.generate(dim, (i) => sin((hash + i) * 0.123456));
    double norm = 0;
    for (final v in random) {
      norm += v * v;
    }
    norm = norm <= 0 ? 1.0 : sqrt(norm);
    return Float32List.fromList(random.map((v) => v / norm).toList());
  }

  /// Align face using eye keypoints with affine transformation.
  ///
  /// Takes a full image and face detection with eye keypoints, rotates and scales
  /// the face so that eyes are horizontally aligned at a standard position,
  /// then crops to 112x112.
  ///
  /// Returns the aligned face crop as image bytes (RGB, 112x112).
  Uint8List alignFace({
    required Uint8List imageBytes,
    required FaceDetection faceDetection,
  }) {
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      throw StateError('Failed to decode image for face alignment');
    }

    // Find eye keypoints (BlazeFace uses 'right_eye' and 'left_eye')
    FaceKeypoint? rightEye;
    FaceKeypoint? leftEye;

    for (final kp in faceDetection.keypoints) {
      if (kp.name == 'right_eye') {
        rightEye = kp;
      } else if (kp.name == 'left_eye') {
        leftEye = kp;
      }
    }

    if (rightEye == null || leftEye == null) {
      _logger.warning('Eye keypoints not found, falling back to center crop');
      return _centerCropFace(imageBytes, faceDetection);
    }

    final imgWidth = decodedImage.width.toDouble();
    final imgHeight = decodedImage.height.toDouble();

    // Convert normalized keypoints to pixel coordinates
    final rightEyeX = rightEye.x * imgWidth;
    final rightEyeY = rightEye.y * imgHeight;
    final leftEyeX = leftEye.x * imgWidth;
    final leftEyeY = leftEye.y * imgHeight;

    // Calculate angle between eyes for rotation
    final dY = leftEyeY - rightEyeY;
    final dX = leftEyeX - rightEyeX;
    final angle = atan2(dY, dX);

    // Desired eye positions in the aligned 112x112 image
    // Standard: eyes at (38, 48) and (74, 48) for 112x112 output
    const desiredRightEyeX = 38.0;
    const desiredLeftEyeX = 74.0;
    const desiredEyeY = 48.0;
    const desiredDist = desiredLeftEyeX - desiredRightEyeX; // 36

    // Current eye distance
    final currentDist = sqrt(dX * dX + dY * dY);

    // Scale factor
    final scale = desiredDist / currentDist;

    // Center point between eyes
    final eyesCenterX = (rightEyeX + leftEyeX) / 2;
    final eyesCenterY = (rightEyeY + leftEyeY) / 2;

    // Build affine transformation
    // 1. Translate to origin at eyes center
    // 2. Rotate by -angle (to make eyes horizontal)
    // 3. Scale by scale factor
    // 4. Translate to desired center in output image (56, 48)
    final cosVal = cos(angle);
    final sinVal = sin(angle);

    // Transformation matrix components for: output = M * input
    // We want to map from output coordinates to input coordinates for sampling
    // So we use the inverse transformation
    final invScale = 1.0 / scale;
    final invCos = cosVal;  // cos(-angle) = cos(angle)
    final invSin = -sinVal; // sin(-angle) = -sin(angle)

    // Desired output center
    const outCenterX = 56.0;
    const outCenterY = 48.0;

    // Create output image (112x112)
    final alignedFace = img.Image(width: _inputSize, height: _inputSize);

    // For each pixel in output, find corresponding input pixel
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        // Map output coordinates to input coordinates
        final dx = x - outCenterX;
        final dy = y - outCenterY;

        // Apply inverse rotation and scale
        final srcX = eyesCenterX + (dx * invCos - dy * invSin) * invScale;
        final srcY = eyesCenterY + (dx * invSin + dy * invCos) * invScale;

        // Bilinear interpolation from source image
        if (srcX >= 0 && srcX < imgWidth - 1 && srcY >= 0 && srcY < imgHeight - 1) {
          final x1 = srcX.floor();
          final y1 = srcY.floor();
          final x2 = x1 + 1;
          final y2 = y1 + 1;

          final wx = srcX - x1;
          final wy = srcY - y1;

          final p11 = decodedImage.getPixel(x1, y1);
          final p12 = decodedImage.getPixel(x2, y1);
          final p21 = decodedImage.getPixel(x1, y2);
          final p22 = decodedImage.getPixel(x2, y2);

          final r = (1 - wx) * (1 - wy) * p11.r +
                    wx * (1 - wy) * p12.r +
                    (1 - wx) * wy * p21.r +
                    wx * wy * p22.r;
          final g = (1 - wx) * (1 - wy) * p11.g +
                    wx * (1 - wy) * p12.g +
                    (1 - wx) * wy * p21.g +
                    wx * wy * p22.g;
          final b = (1 - wx) * (1 - wy) * p11.b +
                    wx * (1 - wy) * p12.b +
                    (1 - wx) * wy * p21.b +
                    wx * wy * p22.b;

          alignedFace.setPixel(x, y, img.ColorRgb8(r.round(), g.round(), b.round()));
        } else {
          // Outside bounds - fill with gray
          alignedFace.setPixel(x, y, img.ColorRgb8(128, 128, 128));
        }
      }
    }

    // Convert to bytes
    return Uint8List.fromList(alignedFace.toUint8List().buffer.asUint8List());
  }

  /// Fallback: center crop face bounding box and resize to 112x112.
  Uint8List _centerCropFace(Uint8List imageBytes, FaceDetection faceDetection) {
    final decodedImage = img.decodeImage(imageBytes)!;
    final imgWidth = decodedImage.width;
    final imgHeight = decodedImage.height;

    // Convert normalized bbox to pixel coordinates
    final x = (faceDetection.x * imgWidth).round();
    final y = (faceDetection.y * imgHeight).round();
    final w = (faceDetection.width * imgWidth).round();
    final h = (faceDetection.height * imgHeight).round();

    // Crop face region
    final cropped = img.copyCrop(decodedImage, x: x, y: y, width: w, height: h);

    // Resize to 112x112
    final resized = img.copyResize(
      cropped,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    return Uint8List.fromList(resized.toUint8List().buffer.asUint8List());
  }

  /// Generate face embedding from full image using BlazeFace detection for alignment.
  ///
  /// This method:
  /// 1. Takes full image bytes and a FaceDetection with keypoints
  /// 2. Aligns the face using eye keypoints (affine transform)
  /// 3. Generates embedding from the aligned face
  Future<Float32List> generateEmbeddingFromFace({
    required Uint8List imageBytes,
    required FaceDetection faceDetection,
  }) async {
    await _ensureInitialized();

    if (_session == null) {
      throw StateError('ONNX session not initialized');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Align face using eye keypoints
      final alignedFaceBytes = alignFace(
        imageBytes: imageBytes,
        faceDetection: faceDetection,
      );

      // Preprocess aligned face
      final inputTensor = _preprocessAlignedFace(alignedFaceBytes);

      // Run inference
      final outputs = _session!.run(
        OrtRunOptions(),
        {_session!.inputNames.first: inputTensor},
      );

      stopwatch.stop();

      // Parse output
      final outputTensor = outputs[0] as OrtValueTensor?;
      if (outputTensor == null) {
        throw StateError('No output tensor from model');
      }

      final outputValue = outputTensor.value;
      if (outputValue is! Float32List) {
        throw StateError('Unexpected output tensor type: ${outputValue.runtimeType}');
      }

      final embedding = Float32List.fromList(outputValue);

      // L2 normalize the embedding
      final normalized = _l2Normalize(embedding);

      _logger.debug('Face embedding generated (${normalized.length}D) in ${stopwatch.elapsedMilliseconds}ms (with alignment)');

      return normalized;
    } catch (e, st) {
      _logger.error('Failed to generate face embedding with alignment', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Preprocess an already-aligned face crop (112x112) for embedding model.
  OrtValueTensor _preprocessAlignedFace(Uint8List alignedFaceBytes) {
    final decodedImage = img.decodeImage(alignedFaceBytes);
    if (decodedImage == null) {
      throw StateError('Failed to decode aligned face image');
    }

    // Ensure it's the right size
    img.Image resized = decodedImage;
    if (decodedImage.width != _inputSize || decodedImage.height != _inputSize) {
      resized = img.copyResize(
        decodedImage,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );
    }

    // Convert to normalized [-1, 1] NCHW tensor [1, 3, H, W]
    final inputData = Float32List(1 * 3 * _inputSize * _inputSize);
    var idx = 0;

    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _inputSize; y++) {
        for (var x = 0; x < _inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          final value = (c == 0 ? pixel.r : c == 1 ? pixel.g : pixel.b) / 127.5 - 1.0;
          inputData[idx++] = value;
        }
      }
    }

    return OrtValueTensor.createTensorWithDataList(inputData, [1, 3, _inputSize, _inputSize]);
  }

  @override
  Future<void> initialize() async {
    await _ensureInitialized();
  }

  @override
  Future<void> warmUp() async {
    await _ensureInitialized();
    if (_session == null) return;

    try {
      // Run dummy inference to warm up
      final dummyInput = Float32List(1 * 3 * _inputSize * _inputSize);
      final tensor = OrtValueTensor.createTensorWithDataList(dummyInput, [1, 3, _inputSize, _inputSize]);
      _session!.run(
        OrtRunOptions(),
        {_session!.inputNames.first: tensor},
      );
      _logger.info('Face embedding model warmed up');
    } catch (e) {
      _logger.warning('Face embedding warm-up failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    _session = null;
    _initialized = false;
  }
}