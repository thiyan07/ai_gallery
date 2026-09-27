import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../../core/logging/app_logger.dart';
import '../../core/services/model_downloader.dart';
import '../../core/services/model_manager.dart';
import '../../core/utils/async_init_guard.dart';
import '../../core/utils/device_capabilities.dart';
import '../../domain/models/face_detection.dart';
import 'face_detection_provider.dart';

/// Local face detection using ONNX Runtime with BlazeFace model.
///
/// BlazeFace is a lightweight face detector designed for mobile devices.
/// It detects faces with bounding boxes and 6 key landmarks (2 eyes, nose, 2 mouth corners, 2 ears).
///
/// Model variants:
/// - blaze_face_short_range: 128x128 input, faster, good for selfies/close faces (default)
/// - blaze_face_full_range: 256x256 input, slower, better for distant faces
class BlazeFaceProvider implements FaceDetectionProvider {
  /// Create a BlazeFace provider.
  ///
  /// [logger] - Application logger.
  /// [modelManager] - Manages model downloading from Hugging Face.
  /// [modelAssetPath] - Optional bundled asset path for fallback.
  /// [modelVariant] - Model variant: 'short_range' (128x128) or 'full_range' (256x256).
  /// [confidenceThreshold] - Minimum confidence for detections (0.0-1.0).
  /// [iouThreshold] - IoU threshold for non-maximum suppression (0.0-1.0).
  /// [maxFaces] - Maximum number of faces to detect.
  BlazeFaceProvider({
    required AppLogger logger,
    required ModelManager modelManager,
    String? modelAssetPath,
    String modelVariant = 'short_range',
    double confidenceThreshold = 0.5,
    double iouThreshold = 0.3,
    int maxFaces = 10,
  })  : _logger = logger,
        _modelManager = modelManager,
        _modelAssetPath = modelAssetPath ?? 'assets/models/blaze_face_short_range.onnx',
        _modelVariant = modelVariant,
        _confidenceThreshold = confidenceThreshold,
        _iouThreshold = iouThreshold,
        _maxFaces = maxFaces;

  final AppLogger _logger;
  final ModelManager _modelManager;
  final String _modelAssetPath;
  final String _modelVariant;
  final double _confidenceThreshold;
  final double _iouThreshold;
  final int _maxFaces;

  OrtSession? _session;
  bool _initialized = false;
  int _inputSize = 128;
  int _numAnchors = 896;
  final _initGuard = AsyncInitGuard();

  // Anchor boxes for BlazeFace (pre-computed for 128x128 input)
  late final List<List<double>> _anchors;

  @override
  String get id => 'blazeface_$_modelVariant';

  @override
  String get name => 'BlazeFace (ONNX): $_modelVariant';

  @override
  Future<bool> get isAvailable async {
    try {
      await _ensureInitialized();
      return _session != null;
    } catch (e) {
      _logger.warning('BlazeFace provider not available: $e');
      return false;
    }
  }

  /// Initialize the ONNX Runtime session with BlazeFace model.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _initGuard.run(_doInitialize);
  }

  Future<void> _doInitialize() async {
    if (_initialized) return;

    try {
      // Set input size based on variant
      _inputSize = _modelVariant == 'full_range' ? 256 : 128;
      _numAnchors = _modelVariant == 'full_range' ? 2016 : 896;

      // Generate anchor boxes
      _anchors = _generateAnchors();

      // Select model in ModelManager (triggers download if needed)
      final modelPreset = _modelVariant == 'full_range' ? 'blaze_face_full_range' : 'blaze_face_short_range';
      _modelManager.selectModel(modelPreset);

      // Try to get model path from ModelManager (downloads if needed with validation)
      ModelDownloadResult? result;
      try {
        result = await _modelManager.getSelectedModelPath();
      } catch (e) {
        _logger.warning('ModelManager not ready, falling back to assets: $e');
      }

      Uint8List modelBytes;
      if (result != null && result.isSuccess && result.localPath.isNotEmpty) {
        _logger.info('Loading BlazeFace model from: ${result.localPath}');
        final file = File(result.localPath);
        modelBytes = await file.readAsBytes();
      } else {
        _logger.info('Loading BlazeFace model from assets: $_modelAssetPath');
        modelBytes = await _loadModelFromAssets();
      }

      // Configure ONNX session options
      final sessionOptions = OrtSessionOptions()
        ..setIntraOpNumThreads(await _getOptimalThreadCount())
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      // Add CPU provider
      sessionOptions.appendCPUProvider(CPUFlags.useArena);

      // Create ONNX session
      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _initialized = true;
      _logger.info('BlazeFaceProvider initialized with model: $modelPreset (input: ${_inputSize}x$_inputSize, anchors: $_numAnchors)');
    } catch (e, st) {
      _logger.error(
        'Failed to initialize BlazeFaceProvider',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Get optimal thread count for ONNX inference.
  Future<int> _getOptimalThreadCount() async {
    final caps = await DeviceCapabilities.instance;
    final cores = caps.cpuCores;
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

  /// Generate anchor boxes for BlazeFace.
  ///
  /// BlazeFace uses a set of predefined anchor boxes at different scales and aspect ratios.
  /// For 128x128 input: 896 anchors (4 feature map scales: 16x16, 8x8, 4x4, 2x2 with 2 anchors each)
  List<List<double>> _generateAnchors() {
    final anchors = <List<double>>[];
    final inputSize = _inputSize.toDouble();

    // BlazeFace anchor configuration (from MediaPipe)
    // For short range (128x128): strides [8, 16, 32, 64] with 2 anchors each per location
    final List<double> strides;
    final List<List<double>> anchorSizes;

    if (_modelVariant == 'full_range') {
      // Full range: 256x256, strides [8, 16, 32, 64, 128], feature maps 32x32, 16x16, 8x8, 4x4, 2x2
      strides = [8.0, 16.0, 32.0, 64.0, 128.0];
      anchorSizes = [
        [0.1, 0.141],   // 16x16 feature map
        [0.2, 0.282],   // 8x8
        [0.4, 0.564],   // 4x4
        [0.8, 1.128],   // 2x2
        [1.6, 2.256],   // 1x1 (if needed)
      ];
    } else {
      // Short range: 128x128, strides [8, 16, 32, 64], feature maps 16x16, 8x8, 4x4, 2x2
      strides = [8.0, 16.0, 32.0, 64.0];
      anchorSizes = [
        [0.1, 0.141],   // 16x16
        [0.2, 0.282],   // 8x8
        [0.4, 0.564],   // 4x4
        [0.8, 1.128],   // 2x2
      ];
    }

    for (var i = 0; i < strides.length; i++) {
      final stride = strides[i];
      final featureMapSize = (inputSize / stride).round();
      final baseAnchorSize = anchorSizes[i];

      for (var y = 0; y < featureMapSize; y++) {
        for (var x = 0; x < featureMapSize; x++) {
          // Anchor center (normalized)
          final cx = (x + 0.5) * stride / inputSize;
          final cy = (y + 0.5) * stride / inputSize;

          for (final size in baseAnchorSize) {
            anchors.add([cx, cy, size, size]);
          }
        }
      }
    }

    // Ensure we have the expected number of anchors
    if (anchors.length != _numAnchors) {
      _logger.warning('Generated ${anchors.length} anchors, expected $_numAnchors');
    }

    return anchors;
  }

  void resetForRetry() {
    _session?.release();
    _session = null;
    _initialized = false;
    _initGuard.reset();
  }

  @override
  Future<List<FaceDetection>> detectFaces(Uint8List imageBytes) async {
    await _ensureInitialized();

    if (_session == null) {
      throw StateError('MODEL_NOT_READY: Face detection session not initialized — please download BlazeFace model from Settings > AI Models');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Decode image to get dimensions
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        throw StateError('Failed to decode image');
      }

      final imageWidth = decodedImage.width;
      final imageHeight = decodedImage.height;

      // Preprocess: resize to input size, normalize, convert to NCHW tensor
      final inputTensor = _preprocessImage(imageBytes);

      // Run inference
      final runOptions = OrtRunOptions();
      try {
        final outputs = _session!.run(
          runOptions,
          {_session!.inputNames.first: inputTensor},
        );

        stopwatch.stop();

        // Parse BlazeFace output.
        // MediaPipe-style models produce two output tensors:
        //   outputs[0] = regressors  [1, num_anchors, 16]  (bbox + keypoints)
        //   outputs[1] = scores      [1, num_anchors, 1]   (face confidence, logit)
        // Some combined models produce a single [1, num_anchors, 16] tensor
        // where index 4 is confidence — we detect which variant we have.
        if (outputs.isEmpty) {
          throw StateError('No output from model');
        }

        final regressorsTensor = outputs[0] as OrtValueTensor?;
        if (regressorsTensor == null) {
          throw StateError('No regressors tensor from model');
        }

        OrtValueTensor? scoresTensor;
        if (outputs.length >= 2) {
          scoresTensor = outputs[1] as OrtValueTensor?;
        }

        final detections = _parseBlazeFaceOutput(
          regressorsTensor,
          scoresTensor,
          imageWidth,
          imageHeight,
        );

        _logger.debug('BlazeFace detected ${detections.length} faces in ${stopwatch.elapsedMilliseconds}ms');

        return detections;
      } finally {
        runOptions.release();
      }
    } catch (e, st) {
      _logger.error('Failed to detect faces', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Preprocess image for BlazeFace input: [1, 3, H, W] NCHW format, normalized to [-1, 1].
  OrtValueTensor _preprocessImage(Uint8List imageBytes) {
    final decodedImage = img.decodeImage(imageBytes)!;

    // Resize to input size with letterboxing to maintain aspect ratio
    final resized = img.copyResize(
      decodedImage,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

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

  /// Parse BlazeFace output -> FaceDetection list.
  ///
  /// Two model variants are supported:
  /// 1. Dual-output (MediaPipe-style): regressors [1, N, 16] + scores [1, N, 1]
  ///    - regressors 0-3: bbox regression (dx, dy, dw, dh)
  ///    - regressors 4-13: 5 keypoints * 2
  ///    - scores: face confidence logit (apply sigmoid)
  /// 2. Combined: single [1, N, 16] tensor
  ///    - 0-3: bbox, 4: confidence (sigmoid), 5-14: keypoints
  List<FaceDetection> _parseBlazeFaceOutput(
    OrtValueTensor regressorsTensor,
    OrtValueTensor? scoresTensor,
    int imageWidth,
    int imageHeight,
  ) {
    final regValue = regressorsTensor.value;
    if (regValue is! Float32List) {
      throw StateError('Unexpected regressors type: ${regValue.runtimeType}');
    }
    final regData = regValue;

    // Determine if this is a dual-output model (scores separate)
    final bool hasSeparateScores = scoresTensor != null;
    Float32List? scoreData;
    if (hasSeparateScores) {
      final sVal = scoresTensor!.value;
      if (sVal is Float32List) {
        scoreData = sVal;
      }
    }

    final detections = <FaceDetection>[];
    final rawDetections = <_RawDetection>[];

    for (var i = 0; i < _numAnchors; i++) {
      final regBase = i * 16;
      if (regBase + 15 >= regData.length) break;

      // Confidence: from separate scores tensor or index 4 of combined tensor
      final double confidence;
      if (hasSeparateScores && scoreData != null) {
        final scoreIdx = i;
        if (scoreIdx >= scoreData.length) break;
        confidence = _sigmoid(scoreData[scoreIdx]);
      } else {
        confidence = _sigmoid(regData[regBase + 4]);
      }

      if (confidence < _confidenceThreshold) continue;

      // Bbox regression (indices 0-3)
      final dx = regData[regBase + 0];
      final dy = regData[regBase + 1];
      final dw = regData[regBase + 2];
      final dh = regData[regBase + 3];

      // Decode bbox from anchor
      final anchor = _anchors[i];
      final anchorCx = anchor[0];
      final anchorCy = anchor[1];
      final anchorW = anchor[2];
      final anchorH = anchor[3];

      final cx = anchorCx + dx * anchorW;
      final cy = anchorCy + dy * anchorH;
      final w = anchorW * exp(dw);
      final h = anchorH * exp(dh);

      // Keypoints: in dual-output models, start at index 4; in combined, at index 5
      final kpOffset = hasSeparateScores ? 4 : 5;
      final keypoints = <FaceKeypoint>[];
      const keypointNames = ['right_eye', 'left_eye', 'nose', 'mouth_right', 'mouth_left'];

      for (var k = 0; k < 5; k++) {
        final kx = regData[regBase + kpOffset + k * 2];
        final ky = regData[regBase + kpOffset + k * 2 + 1];

        final kpx = anchorCx + kx * anchorW;
        final kpy = anchorCy + ky * anchorH;

        keypoints.add(FaceKeypoint(
          name: keypointNames[k],
          x: kpx.clamp(0.0, 1.0),
          y: kpy.clamp(0.0, 1.0),
        ));
      }

      rawDetections.add(_RawDetection(
        cx: cx,
        cy: cy,
        w: w,
        h: h,
        confidence: confidence,
        keypoints: keypoints,
      ));
    }

    // Apply Non-Maximum Suppression
    final nmsDetections = _nms(rawDetections);

    // Convert to FaceDetection objects (limit to maxFaces)
    for (var i = 0; i < min(nmsDetections.length, _maxFaces); i++) {
      final det = nmsDetections[i];

      // Convert from normalized [0,1] center+size to normalized [0,1] x,y,w,h
      // Note: The cx/cy are already normalized to [0,1] relative to input size
      final x = (det.cx - det.w / 2).clamp(0.0, 1.0);
      final y = (det.cy - det.h / 2).clamp(0.0, 1.0);
      final w = det.w.clamp(0.0, 1.0);
      final h = det.h.clamp(0.0, 1.0);

      detections.add(FaceDetection(
        x: x,
        y: y,
        width: w,
        height: h,
        confidence: det.confidence,
        keypoints: det.keypoints,
      ));
    }

    return detections;
  }

  /// Sigmoid function.
  double _sigmoid(double x) {
    return 1.0 / (1.0 + exp(-x));
  }

  /// Non-Maximum Suppression for face detections.
  List<_RawDetection> _nms(List<_RawDetection> detections) {
    if (detections.isEmpty) return [];

    // Sort by confidence descending
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    final keep = <_RawDetection>[];
    final suppressed = List.filled(detections.length, false);

    for (var i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;

      final det = detections[i];
      keep.add(det);

      // Suppress overlapping boxes with lower confidence
      for (var j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;

        if (_iou(det, detections[j]) > _iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return keep;
  }

  /// Calculate IoU between two detections.
  double _iou(_RawDetection det1, _RawDetection det2) {
    // Convert to [x1, y1, x2, y2]
    final x1_1 = det1.cx - det1.w / 2;
    final y1_1 = det1.cy - det1.h / 2;
    final x2_1 = det1.cx + det1.w / 2;
    final y2_1 = det1.cy + det1.h / 2;

    final x1_2 = det2.cx - det2.w / 2;
    final y1_2 = det2.cy - det2.h / 2;
    final x2_2 = det2.cx + det2.w / 2;
    final y2_2 = det2.cy + det2.h / 2;

    // Intersection
    final interX1 = max(x1_1, x1_2);
    final interY1 = max(y1_1, y1_2);
    final interX2 = min(x2_1, x2_2);
    final interY2 = min(y2_1, y2_2);

    final interW = max(0.0, interX2 - interX1);
    final interH = max(0.0, interY2 - interY1);
    final interArea = interW * interH;

    // Union
    final area1 = (x2_1 - x1_1) * (y2_1 - y1_1);
    final area2 = (x2_2 - x1_2) * (y2_2 - y1_2);
    final unionArea = area1 + area2 - interArea;

    return unionArea > 0 ? interArea / unionArea : 0;
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
      final runOptions = OrtRunOptions();
      try {
        _session!.run(
          runOptions,
          {_session!.inputNames.first: tensor},
        );
        _logger.info('BlazeFace model warmed up');
      } finally {
        runOptions.release();
      }
    } catch (e) {
      _logger.warning('BlazeFace warm-up failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    _session?.release();
    _session = null;
    _initialized = false;
    _initGuard.reset();
  }
}

/// Raw detection with keypoints before NMS.
class _RawDetection {
  _RawDetection({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
    required this.confidence,
    required this.keypoints,
  });

  final double cx, cy, w, h;
  final double confidence;
  final List<FaceKeypoint> keypoints;
}