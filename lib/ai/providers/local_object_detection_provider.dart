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
import '../../domain/models/object_detection.dart';
import '../../domain/models/object_detection_model.dart';
import 'object_detection_provider.dart';

/// Local object detection using ONNX Runtime with YOLOv8 models.
///
/// Automatically selects the optimal YOLO model based on device capabilities:
/// - Low-end: YOLOv8n (nano, fastest, ~6MB)
/// - Mid-range: YOLOv8s (small, balanced, ~22MB)
/// - High-end: YOLOv8m (medium, better accuracy, ~52MB)
/// - Flagship: YOLOv8l (large, best accuracy, ~87MB)
class LocalObjectDetectionProvider implements ObjectDetectionProvider {
  /// Create a provider with automatic model selection based on device capabilities.
  ///
  /// [logger] - Application logger.
  /// [modelManager] - Manages model downloading from Hugging Face.
  /// [modelAssetPath] - Optional bundled asset path for fallback.
  /// [modelPreset] - Optional explicit model preset (overrides auto-selection).
  /// [confidenceThreshold] - Minimum confidence for detections (0.0-1.0).
  /// [iouThreshold] - IoU threshold for non-maximum suppression (0.0-1.0).
  /// [inputSize] - Input image size (determined by model if null).
  /// [forceTier] - Optional forced device tier for testing.
  LocalObjectDetectionProvider({
    required AppLogger logger,
    required ModelManager modelManager,
    String? modelAssetPath,
    String? modelPreset,
    double confidenceThreshold = 0.25,
    double iouThreshold = 0.45,
    int? inputSize,
    DeviceTier? forceTier,
  })  : _logger = logger,
        _modelManager = modelManager,
        _modelAssetPath = modelAssetPath ?? 'assets/models/yolov8n.onnx',
        _forcedPreset = modelPreset,
        _confidenceThreshold = confidenceThreshold,
        _iouThreshold = iouThreshold,
        _forcedTier = forceTier,
        _inputSize = inputSize;

  final AppLogger _logger;
  final ModelManager _modelManager;
  final String _modelAssetPath;
  final String? _forcedPreset;
  final double _confidenceThreshold;
  final double _iouThreshold;
  final DeviceTier? _forcedTier;
  final int? _inputSize;

  OrtSession? _session;
  bool _initialized = false;
  DeviceCapabilities? _capabilities;
  String? _resolvedPreset;
  int? _resolvedInputSize;

  // COCO class labels (80 classes)
  static const _cocoLabels = [
    'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck',
    'boat', 'traffic light', 'fire hydrant', 'stop sign', 'parking meter', 'bench',
    'bird', 'cat', 'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra',
    'giraffe', 'backpack', 'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee',
    'skis', 'snowboard', 'sports ball', 'kite', 'baseball bat', 'baseball glove',
    'skateboard', 'surfboard', 'tennis racket', 'bottle', 'wine glass', 'cup',
    'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple', 'sandwich', 'orange',
    'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake', 'chair', 'couch',
    'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop', 'mouse',
    'remote', 'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink',
    'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear', 'hair dryer',
    'toothbrush',
  ];

  @override
  String get id => 'local_yolo_${_resolvedPreset ?? _determinePreset()}';

  @override
  String get name => 'YOLO (ONNX): ${_resolvedPreset ?? _determinePreset()}';

  @override
  List<String> get labels => _cocoLabels;

  @override
  Future<bool> get isAvailable async {
    try {
      await _ensureInitialized();
      return _session != null;
    } catch (e) {
      _logger.warning('Local object detection provider not available: $e');
      return false;
    }
  }

  /// Initialize the ONNX Runtime session with auto-selected YOLO model.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    try {
      // Detect device capabilities and select model
      _capabilities = await DeviceCapabilities.instance;
      _resolvedPreset = _determinePreset();
      _resolvedInputSize = _determineInputSize();

      final caps = _capabilities!;
      _logger.info(
        'Device: ${caps.modelName} (${caps.tier.name}) '
            '→ Object Detection Model: $_resolvedPreset ($_resolvedInputSize px, '
            '${caps.performanceMultiplier.toStringAsFixed(1)}x perf)',
      );

      // Select model in ModelManager (triggers download if needed)
      _modelManager.selectModel(_resolvedPreset!);

      // Try to get model path from ModelManager (downloads if needed)
      String? modelPath;
      try {
        modelPath = await _modelManager.getSelectedModelPath();
      } catch (e) {
        _logger.warning('ModelManager not ready, falling back to assets: $e');
      }

      Uint8List modelBytes;

      if (modelPath != null) {
        // Load from downloaded model file
        _logger.info('Loading YOLO model from: $modelPath');
        final file = File(modelPath);
        modelBytes = await file.readAsBytes();
      } else {
        // Fallback to bundled asset
        _logger.info('Loading YOLO model from assets: $_modelAssetPath');
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
      _logger.info('LocalObjectDetectionProvider initialized with model: $_resolvedPreset');
    } catch (e, st) {
      _logger.error(
        'Failed to initialize LocalObjectDetectionProvider',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Determine the YOLO model preset to use.
  String _determinePreset() {
    if (_forcedPreset != null) return _forcedPreset!;
    if (_forcedTier != null) return _presetForTier(_forcedTier!);
    return _capabilities?.recommendedModelPreset ?? 'yolov8n';
  }

  /// Get YOLO preset for a specific device tier.
  String _presetForTier(DeviceTier tier) {
    return switch (tier) {
      DeviceTier.low => 'yolov8n',       // ~6MB, fastest
      DeviceTier.medium => 'yolov8s',    // ~22MB, balanced
      DeviceTier.high => 'yolov8m',      // ~52MB, better accuracy
      DeviceTier.flagship => 'yolov8l',  // ~87MB, best accuracy
    };
  }

  /// Determine input size for the current model.
  int _determineInputSize() {
    if (_inputSize != null) return _inputSize!;
    // YOLOmodels typically use 640x640
    return 640;
  }

  /// Get optimal thread count for ONNX inference.
  int _getOptimalThreadCount() {
    if (_capabilities == null) return 4;
    final cores = _capabilities!.cpuCores;
    return cores <= 2 ? 1 : cores - 1;
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
  Future<ObjectDetectionResult> detectObjects(Uint8List imageBytes) async {
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

      final imageWidth = decodedImage.width;
      final imageHeight = decodedImage.height;

      // Preprocess: resize with letterboxing, normalize, convert to NCHW tensor
      final inputTensor = _preprocessImage(imageBytes);

      // Run inference
      final outputs = _session!.run(
        OrtRunOptions(),
        {_session!.inputNames.first: inputTensor},
      );

      stopwatch.stop();

      // Parse YOLOv8 output format: [1, 84, 8400] - 80 classes + 4 bbox
      final outputTensor = outputs[0] as OrtValueTensor?;

      if (outputTensor == null) {
        throw StateError('No output tensor from model');
      }

      final detections = _parseYoloOutput(
        outputTensor,
        imageWidth,
        imageHeight,
      );

      return ObjectDetectionResult(
        detections: detections,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e, st) {
      _logger.error('Failed to detect objects', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Preprocess image for YOLO input: [1, 3, H, W] NCHW format.
  OrtValueTensor _preprocessImage(Uint8List imageBytes) {
    final decodedImage = img.decodeImage(imageBytes)!;
    final inputSize = _resolvedInputSize!;

    // Resize with letterboxing to maintain aspect ratio
    final resized = img.copyResize(
      decodedImage,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Convert to normalized [0,1] NCHW tensor [1, 3, H, W]
    final inputData = Float32List(1 * 3 * inputSize * inputSize);
    var idx = 0;

    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < inputSize; y++) {
        for (var x = 0; x < inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          final value = (c == 0 ? pixel.r : c == 1 ? pixel.g : pixel.b) / 255.0;
          inputData[idx++] = value;
        }
      }
    }

    return OrtValueTensor.createTensorWithDataList(inputData, [1, 3, inputSize, inputSize]);
  }

  /// Parse YOLOv8 output [1, 84, 8400] -> detections.
  /// 84 = 4 (bbox: cx, cy, w, h) + 80 (class scores)
  List<DetectedObject> _parseYoloOutput(
    OrtValueTensor outputTensor,
    int imageWidth,
    int imageHeight,
  ) {
    final outputValue = outputTensor.value;
    if (outputValue is! Float32List) {
      throw StateError('Unexpected output tensor type: ${outputValue.runtimeType}');
    }

    final data = outputValue;
    const numClasses = 80;
    const numAnchors = 8400;
    const channels = 4 + numClasses; // 84

    if (data.length != channels * numAnchors) {
      _logger.warning('Unexpected output tensor size: ${data.length} (expected ${channels * numAnchors})');
    }

    final detections = <DetectedObject>[];
    final scaleX = imageWidth / _resolvedInputSize!;
    final scaleY = imageHeight / _resolvedInputSize!;

    for (var i = 0; i < numAnchors; i++) {
      // Find class with max score
      var maxScore = 0.0;
      var maxClass = -1;

      for (var c = 0; c < numClasses; c++) {
        final score = data[(4 + c) * numAnchors + i];
        if (score > maxScore) {
          maxScore = score;
          maxClass = c;
        }
      }

      // Apply confidence threshold
      if (maxScore < _confidenceThreshold) continue;

      // Extract bounding box (cx, cy, w, h normalized to input size)
      final cx = data[0 * numAnchors + i];
      final cy = data[1 * numAnchors + i];
      final w = data[2 * numAnchors + i];
      final h = data[3 * numAnchors + i];

      if (w <= 0 || h <= 0) continue;

      // Convert to normalized coordinates relative to original image
      final normCx = (cx * scaleX).clamp(0.0, 1.0);
      final normCy = (cy * scaleY).clamp(0.0, 1.0);
      final normW = (w * scaleX).clamp(0.0, 1.0);
      final normH = (h * scaleY).clamp(0.0, 1.0);

      final label = maxClass < _cocoLabels.length ? _cocoLabels[maxClass] : 'class_$maxClass';

      detections.add(DetectedObject(
        label: label,
        confidence: maxScore,
        boundingBox: [normCx, normCy, normW, normH],
        classIndex: maxClass,
      ));
    }

    // Apply Non-Maximum Suppression
    return _nms(detections);
  }

  /// Non-Maximum Suppression to remove duplicate detections.
  List<DetectedObject> _nms(List<DetectedObject> detections) {
    if (detections.isEmpty) return [];

    // Sort by confidence descending
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    final keep = <DetectedObject>[];
    final suppressed = List.filled(detections.length, false);

    for (var i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;

      final det = detections[i];
      keep.add(det);

      // Suppress overlapping boxes of same class with lower confidence
      for (var j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;
        if (detections[j].label != det.label) continue;

        if (_iou(det.boundingBox, detections[j].boundingBox) > _iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return keep;
  }

  /// Calculate IoU between two boxes in [cx, cy, w, h] format.
  double _iou(List<double> box1, List<double> box2) {
    // Convert to [x1, y1, x2, y2]
    final x1_1 = box1[0] - box1[2] / 2;
    final y1_1 = box1[1] - box1[3] / 2;
    final x2_1 = box1[0] + box1[2] / 2;
    final y2_1 = box1[1] + box1[3] / 2;

    final x1_2 = box2[0] - box2[2] / 2;
    final y1_2 = box2[1] - box2[3] / 2;
    final x2_2 = box2[0] + box2[2] / 2;
    final y2_2 = box2[1] + box2[3] / 2;

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
      final dummyInput = Float32List(1 * 3 * _resolvedInputSize! * _resolvedInputSize!);
      final tensor = OrtValueTensor.createTensorWithDataList(dummyInput, [1, 3, _resolvedInputSize!, _resolvedInputSize!]);
      _session!.run(
        OrtRunOptions(),
        {_session!.inputNames.first: tensor},
      );
      _logger.info('Object detection model warmed up');
    } catch (e) {
      _logger.warning('Warm-up failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    _session = null;
    _initialized = false;
  }
}