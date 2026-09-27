import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../../core/logging/app_logger.dart';
import '../../core/services/model_manager.dart';
import '../../core/utils/async_init_guard.dart';
import '../../core/utils/device_capabilities.dart';
import '../../domain/models/object_detection_model.dart';
import 'object_detection_provider.dart';

/// PaddleOCR text detector + recognizer using ONNX Runtime.

/// Simple tuple class to hold two values.
class _Tuple {
  final String item1;
  final double item2;

  _Tuple(this.item1, this.item2);
}
///
/// PaddleOCR is a state-of-the-art OCR system with:
/// - Text detection (DB/DBNet): finds text regions in images (640x640 input)
/// - Text recognition (CRNN/SVTR): recognizes text in detected regions (32x320 input, 6625 charset)
class PaddleOcrProvider implements ObjectDetectionProvider {
  /// Create a PaddleOCR provider.
  ///
  /// [logger] - Application logger.
  /// [modelManager] - Manages model downloading from Hugging Face.
  /// [detectorAssetPath] - Optional bundled asset path for detector fallback.
  /// [recognizerAssetPath] - Optional bundled asset path for recognizer fallback.
  /// [detectorInputSize] - Detector input size (default 640).
  /// [recognizerInputSize] - Recognizer input size (default 320).
  /// [charsetPath] - Path to charset file (optional).
  PaddleOcrProvider({
    required AppLogger logger,
    required ModelManager modelManager,
    String? detectorAssetPath,
    String? recognizerAssetPath,
    int detectorInputSize = 640,
    int recognizerInputSize = 320,
    String? charsetPath,
  })  : _logger = logger,
        _modelManager = modelManager,
        _detectorAssetPath = detectorAssetPath ?? 'assets/models/ppocr_det.onnx',
        _recognizerAssetPath = recognizerAssetPath ?? 'assets/models/ppocr_rec.onnx',
        _detectorInputSize = detectorInputSize,
        _recognizerInputSize = recognizerInputSize,
        _charsetPath = charsetPath;

  final AppLogger _logger;
  final ModelManager _modelManager;
  final String _detectorAssetPath;
  final String _recognizerAssetPath;
  final int _detectorInputSize;
  final int _recognizerInputSize;
  final String? _charsetPath;

  OrtSession? _detectorSession;
  OrtSession? _recognizerSession;
  bool _initialized = false;
  List<String> _charset = _defaultCharset();
  final _initGuard = AsyncInitGuard();

  @override
  String get id => 'paddleocr';

  @override
  String get name => 'PaddleOCR (ONNX)';

  @override
  List<String> get labels => ['text'];

  @override
  Future<bool> get isAvailable async {
    try {
      await _ensureInitialized();
      return _detectorSession != null && _recognizerSession != null;
    } catch (e) {
      _logger.warning('PaddleOCR provider not available: $e');
      return false;
    }
  }

  /// Initialize the ONNX Runtime sessions with PaddleOCR models.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _initGuard.run(_doInitialize);
  }

  Future<void> _doInitialize() async {
    if (_initialized) return;

    try {
      _logger.info('Initializing PaddleOCR...');

      // Load charset if provided
      if (_charsetPath != null) {
        _charset = await _loadCharset(_charsetPath);
      }

      // Initialize detector
      await _initDetector();

      // Initialize recognizer
      await _initRecognizer();

      _initialized = true;
      _logger.info('PaddleOcrProvider initialized (detector: ${_detectorInputSize}px, recognizer: 32x${_recognizerInputSize}px)');
    } catch (e, st) {
      _logger.error(
        'Failed to initialize PaddleOcrProvider',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Initialize the text detector (DBNet).
  Future<void> _initDetector() async {
    _modelManager.selectModel('ppocr_det');

    String? modelPath;
    try {
      final result = await _modelManager.getSelectedModelPath();
      if (result.isSuccess && result.localPath.isNotEmpty) {
        modelPath = result.localPath;
      }
    } catch (e) {
      _logger.warning('ModelManager not ready for detector, falling back to assets: $e');
    }

    Uint8List modelBytes;
    if (modelPath != null && modelPath.isNotEmpty) {
      _logger.info('Loading PaddleOCR detector from: $modelPath');
      final file = File(modelPath);
      modelBytes = await file.readAsBytes();
    } else {
      _logger.info('Loading PaddleOCR detector from assets: $_detectorAssetPath');
      modelBytes = await _loadModelFromAssets(_detectorAssetPath);
    }

    final sessionOptions = OrtSessionOptions()
      ..setIntraOpNumThreads(await _getOptimalThreadCount())
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll)
      ..appendCPUProvider(CPUFlags.useArena);

    _detectorSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
    _logger.info('PaddleOCR detector ONNX session created');
  }

  /// Initialize the text recognizer (SVTR/CRNN).
  Future<void> _initRecognizer() async {
    _modelManager.selectModel('ppocr_rec');

    String? modelPath;
    try {
      final result = await _modelManager.getSelectedModelPath();
      if (result.isSuccess && result.localPath.isNotEmpty) {
        modelPath = result.localPath;
      }
    } catch (e) {
      _logger.warning('ModelManager not ready for recognizer, falling back to assets: $e');
    }

    Uint8List modelBytes;
    if (modelPath != null) {
      _logger.info('Loading PaddleOCR recognizer from: $modelPath');
      final file = File(modelPath);
      modelBytes = await file.readAsBytes();
    } else {
      _logger.info('Loading PaddleOCR recognizer from assets: $_recognizerAssetPath');
      modelBytes = await _loadModelFromAssets(_recognizerAssetPath);
    }

    final sessionOptions = OrtSessionOptions()
      ..setIntraOpNumThreads(await _getOptimalThreadCount())
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll)
      ..appendCPUProvider(CPUFlags.useArena);

    _recognizerSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
    _logger.info('PaddleOCR recognizer ONNX session created (charset: ${_charset.length})');
  }

  /// Get optimal thread count for ONNX inference.
  Future<int> _getOptimalThreadCount() async {
    final caps = await DeviceCapabilities.instance;
    final cores = caps.cpuCores;
    return cores <= 2 ? 1 : min(cores, 4);
  }

  /// Load model bytes from Flutter assets.
  Future<Uint8List> _loadModelFromAssets(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List();
    } catch (e) {
      _logger.error('Failed to load model from assets: $e');
      rethrow;
    }
  }

  /// Load charset from file.
  Future<List<String>> _loadCharset(String path) async {
    try {
      final data = await rootBundle.loadString(path);
      return data.trim().split('\n').where((l) => l.isNotEmpty).toList();
    } catch (e) {
      _logger.warning('Failed to load charset, using default: $e');
      return _defaultCharset();
    }
  }

  /// Default PaddleOCR charset (digits, ascii, common punctuation).
  static List<String> _defaultCharset() {
    final chars = <String>[
      ' ', // blank for CTC
      ...'0123456789'.split(''),
      ...'abcdefghijklmnopqrstuvwxyz'.split(''),
      ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''),
      ...'!@#\$%^&*()_+-=[]{}|;:,.<>?/~`'.split(''),
      ...'"\'\\'.split(''),
    ];
    return chars;
  }

  void resetForRetry() {
    _detectorSession?.release();
    _recognizerSession?.release();
    _detectorSession = null;
    _recognizerSession = null;
    _initialized = false;
    _initGuard.reset();
  }

  @override
  Future<ObjectDetectionResult> detectObjects(Uint8List imageBytes) async {
    await _ensureInitialized();

    if (_detectorSession == null || _recognizerSession == null) {
      throw StateError('MODEL_NOT_READY: OCR sessions not initialized — please download PaddleOCR models from Settings > AI Models');
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

      // Step 1: Detect text regions using DBNet
      final regions = await _detectTextRegions(imageBytes);

      await _jobQueueUpdate(0.5);

      // Step 2: Recognize text in each region
      final detections = <DetectedObject>[];

      for (var i = 0; i < regions.length; i++) {
        final region = regions[i];

        // Crop the text region
        final cropped = _cropTextRegion(imageBytes, region, imageWidth, imageHeight);

        // Recognize text
        final result = await _recognizeText(cropped);
        final text = result.item1;
        final confidence = result.item2;

        if (text.isNotEmpty) {
          detections.add(DetectedObject(
            label: text,
            confidence: confidence,
            boundingBox: region, // [x1, y1, x2, y2] normalized
            classIndex: 0,
          ));
        }

        // Update progress
        await _jobQueueUpdate(0.5 + 0.4 * (i + 1) / regions.length);
      }

      stopwatch.stop();

      return ObjectDetectionResult(
        detections: detections,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e, st) {
      _logger.error('PaddleOCR detection failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Progress callback for job queue (no-op placeholder).
  Future<void> _jobQueueUpdate(double progress) async {}

  /// Detect text regions using DBNet detector.
  Future<List<List<double>>> _detectTextRegions(Uint8List imageBytes) async {
    if (_detectorSession == null) return [];

    try {
      // Preprocess for detector (640x640)
      final inputTensor = _preprocessDetector(imageBytes);

      // Run inference
      final runOptions = OrtRunOptions();
      try {
        final outputs = _detectorSession!.run(
          runOptions,
          {_detectorSession!.inputNames.first: inputTensor},
        );

        // Parse outputs: DBNet outputs [1, 1, H, W] probability map
        return _parseDetectorOutput(outputs);
      } finally {
        runOptions.release();
      }
    } catch (e, st) {
      _logger.error('PaddleOCR text detection failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Preprocess image for DBNet detector: [1, 3, 640, 640] NCHW, normalized.
  OrtValueTensor _preprocessDetector(Uint8List imageBytes) {
    final decodedImage = img.decodeImage(imageBytes)!;

    // Resize with aspect ratio preservation to fit within 640x640
    // For DBNet, we typically resize shortest edge to 640 maintaining aspect ratio
    // But for simplicity, we'll use letterbox resize to 640x640
    final resized = img.copyResize(
      decodedImage,
      width: _detectorInputSize,
      height: _detectorInputSize,
      interpolation: img.Interpolation.linear,
    );

    // Convert to normalized [0, 1] NCHW tensor [1, 3, H, W]
    // DBNet uses mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]
    final inputData = Float32List(1 * 3 * _detectorInputSize * _detectorInputSize);
    var idx = 0;

    const mean = [0.485, 0.456, 0.406];
    const std = [0.229, 0.224, 0.225];

    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _detectorInputSize; y++) {
        for (var x = 0; x < _detectorInputSize; x++) {
          final pixel = resized.getPixel(x, y);
          final value = (c == 0 ? pixel.r : c == 1 ? pixel.g : pixel.b) / 255.0;
          final normalized = (value - mean[c]) / std[c];
          inputData[idx++] = normalized;
        }
      }
    }

    return OrtValueTensor.createTensorWithDataList(inputData, [1, 3, _detectorInputSize, _detectorInputSize]);
  }

  /// Parse DBNet output to text regions (bounding boxes).
  List<List<double>> _parseDetectorOutput(List<OrtValue?> outputs) {
    final regions = <List<double>>[];

    try {
      final outputTensor = outputs.first as OrtValueTensor?;
      if (outputTensor == null) {
        _logger.warning('No detector output tensor');
        return regions;
      }

      final data = outputTensor.value;
      if (data is! Float32List && data is! List<double>) {
        _logger.warning('Unexpected detector output type: ${data.runtimeType}');
        return regions;
      }

      final probMap = data is Float32List ? List.from(data) : data as List<double>;
      // DBNet with 640x640 input produces 160x160 probability map (stride 4)
      final outH = _detectorInputSize ~/ 4;
      final outW = _detectorInputSize ~/ 4;

      // Threshold the probability map
      const threshold = 0.3;
      const minArea = 10; // Minimum area in output pixels

      // Find connected components above threshold
      final visited = List<bool>.filled(probMap.length, false);
      final boxes = <_TextBox>[];

      for (int i = 0; i < probMap.length; i++) {
        if (probMap[i] <= threshold || visited[i]) continue;

        // BFS to find connected component
        final component = <int>[];
        final queue = <int>[i];
        visited[i] = true;

        while (queue.isNotEmpty) {
          final curr = queue.removeAt(0);
          component.add(curr);

          final cy = curr ~/ outW;
          final cx = curr % outW;

          // Check 4-connected neighbors
          for (final (dy, dx) in [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
            final ny = cy + dy;
            final nx = cx + dx;
            if (ny >= 0 && ny < outH && nx >= 0 && nx < outW) {
              final nIdx = ny * outW + nx;
              if (!visited[nIdx] && probMap[nIdx] > threshold) {
                visited[nIdx] = true;
                queue.add(nIdx);
              }
            }
          }
        }

        if (component.length >= minArea) {
          // Compute bounding box
          int minX = outW, minY = outH, maxX = 0, maxY = 0;
          for (final idx in component) {
            final y = idx ~/ outW;
            final x = idx % outW;
            minX = min(minX, x);
            maxX = max(maxX, x);
            minY = min(minY, y);
            maxY = max(maxY, y);
          }

          // Convert to normalized coordinates [0, 1]
          final x1 = minX / outW;
          final y1 = minY / outH;
          final x2 = (maxX + 1) / outW;
          final y2 = (maxY + 1) / outH;

          // Compute average confidence
          double sumConf = 0;
          for (final idx in component) {
            sumConf += probMap[idx];
          }
          final avgConf = sumConf / component.length;

          boxes.add(_TextBox(x1: x1, y1: y1, x2: x2, y2: y2, confidence: avgConf));
        }
      }

      // Apply NMS on boxes
      final nmsBoxes = _nms(boxes, 0.3);

      // Convert to output format [x1, y1, x2, y2]
      for (final box in nmsBoxes) {
        regions.add([box.x1, box.y1, box.x2, box.y2]);
      }
    } catch (e) {
      _logger.warning('Failed to parse PaddleOCR detector outputs: $e');
    }

    return regions;
  }

  /// Non-Maximum Suppression for text boxes.
  List<_TextBox> _nms(List<_TextBox> boxes, double iouThreshold) {
    if (boxes.isEmpty) return [];
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));

    final keep = <_TextBox>[];
    final suppressed = List<bool>.filled(boxes.length, false);

    for (var i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;
      final box = boxes[i];
      keep.add(box);
      for (var j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;
        if (_iou(box, boxes[j]) > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return keep;
  }

  /// Calculate IoU between two boxes.
  double _iou(_TextBox a, _TextBox b) {
    final x1 = max(a.x1, b.x1);
    final y1 = max(a.y1, b.y1);
    final x2 = min(a.x2, b.x2);
    final y2 = min(a.y2, b.y2);

    final interW = max(0.0, x2 - x1);
    final interH = max(0.0, y2 - y1);
    final interArea = interW * interH;

    final areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    final unionArea = areaA + areaB - interArea;

    return unionArea > 0 ? interArea / unionArea : 0;
  }

  /// Recognize text in a cropped region using SVTR/CRNN recognizer.
  Future<_Tuple> _recognizeText(Uint8List croppedBytes) async {
    if (_recognizerSession == null) return _Tuple('', 0.0);

    try {
      final inputTensor = _preprocessRecognizer(croppedBytes);

      final runOptions = OrtRunOptions();
      try {
        final outputs = _recognizerSession!.run(
          runOptions,
          {_recognizerSession!.inputNames.first: inputTensor},
        );

        return _parseRecognizerOutput(outputs);
      } finally {
        runOptions.release();
      }
    } catch (e, st) {
      _logger.error('PaddleOCR text recognition failed', error: e, stackTrace: st);
      return _Tuple('', 0.0);
    }
  }

  /// Preprocess cropped image for recognizer: [1, 3, 32, 320] NCHW, normalized to [-1, 1].
  OrtValueTensor _preprocessRecognizer(Uint8List imageBytes) {
    final decodedImage = img.decodeImage(imageBytes)!;

    // Resize to recognizer input size (32 x 320)
    // Maintain aspect ratio with padding
    final resized = _resizeWithPadding(decodedImage, 32, _recognizerInputSize);

    // Convert to normalized [-1, 1] NCHW tensor [1, 3, 32, 320]
    // SVTR typically uses mean=0.5, std=0.5
    const h = 32;
    const w = 320;
    final inputData = Float32List(1 * 3 * h * w);
    var idx = 0;

    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final pixel = resized.getPixel(x, y);
          final value = (c == 0 ? pixel.r : c == 1 ? pixel.g : pixel.b) / 127.5 - 1.0;
          inputData[idx++] = value;
        }
      }
    }

    return OrtValueTensor.createTensorWithDataList(inputData, [1, 3, h, w]);
  }

  /// Resize image maintaining aspect ratio with padding.
  img.Image _resizeWithPadding(img.Image src, int targetH, int targetW) {
    final scale = min(targetW / src.width, targetH / src.height);
    final newW = (src.width * scale).round();
    final newH = (src.height * scale).round();

    final resized = img.copyResize(
      src,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.linear,
    );

    // Create padded canvas
    final canvas = img.Image(width: targetW, height: targetH);

    // Fill with gray (128) - typical for OCR padding
    img.fill(canvas, color: img.ColorRgb8(128, 128, 128));

    // Center the resized image - manual copy instead of copyInto
    final offsetX = (targetW - newW) ~/ 2;
    final offsetY = (targetH - newH) ~/ 2;
    for (int y = 0; y < newH; y++) {
      for (int x = 0; x < newW; x++) {
        final pixel = resized.getPixel(x, y);
        canvas.setPixel(offsetX + x, offsetY + y, pixel);
      }
    }

    return canvas;
  }

  /// Crop text region from original image.
  Uint8List _cropTextRegion(
    Uint8List imageBytes,
    List<double> region, // [x1, y1, x2, y2] normalized
    int imageWidth,
    int imageHeight,
  ) {
    final decodedImage = img.decodeImage(imageBytes)!;

    final x1 = (region[0] * imageWidth).round().clamp(0, imageWidth - 1);
    final y1 = (region[1] * imageHeight).round().clamp(0, imageHeight - 1);
    final x2 = (region[2] * imageWidth).round().clamp(x1 + 1, imageWidth);
    final y2 = (region[3] * imageHeight).round().clamp(y1 + 1, imageHeight);

    final cropWidth = x2 - x1;
    final cropHeight = y2 - y1;

    if (cropWidth <= 0 || cropHeight <= 0) {
      return imageBytes;
    }

    final cropped = img.copyCrop(decodedImage, x: x1, y: y1, width: cropWidth, height: cropHeight);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  /// Parse recognizer output using CTC greedy decoding.
  /// Returns a tuple of [recognized text, average confidence]
  _Tuple _parseRecognizerOutput(List<OrtValue?> outputs) {
    try {
      final outputTensor = outputs.first as OrtValueTensor?;
      if (outputTensor == null) {
        throw StateError('No output tensor');
      }

      final data = outputTensor.value;

      List<double> values;
      if (data is List<double>) {
        values = data;
      } else if (data is Float32List) {
        values = List.from(data);
      } else {
        throw StateError('Unexpected output type: ${data.runtimeType}');
      }

      // Recognizer output: [1, seq_len, vocab_size]
      // Typical seq_len = 25 for 32x320 input, vocab_size = charset length
      // We can derive seq_len from data length since vocab_size is known
      final vocabSize = _charset.length;
      final seqLen = values.length ~/ vocabSize;

      final result = <String>[];
      int? prevChar;
      double totalConfidence = 0;
      int validChars = 0;

      for (int t = 0; t < seqLen; t++) {
        // Find max probability token
        double maxProb = -1;
        int maxIdx = 0;
        final offset = t * vocabSize;

        for (int v = 0; v < vocabSize && offset + v < values.length; v++) {
          final prob = values[offset + v];
          if (prob > maxProb) {
            maxProb = prob;
            maxIdx = v;
          }
        }

        // CTC decoding: skip blank (0) and repeated chars
        if (maxIdx != 0 && maxIdx < _charset.length && maxIdx != prevChar) {
          result.add(_charset[maxIdx]);
          prevChar = maxIdx;
          totalConfidence += maxProb;
          validChars++;
        } else if (maxIdx == 0) {
          prevChar = null; // Reset on blank
        }
      }

      final recognizedText = result.join('');
      final averageConfidence = validChars > 0 ? totalConfidence / validChars : 0.0;
      return _Tuple(recognizedText, averageConfidence);
    } catch (e) {
      _logger.warning('Failed to parse PaddleOCR recognizer outputs: $e');
      return _Tuple('', 0.0);
    }
  }

  @override
  Future<void> initialize() async {
    await _ensureInitialized();
  }

  @override
  Future<void> warmUp() async {
    await _ensureInitialized();
    if (_detectorSession == null || _recognizerSession == null) return;

    try {
      // Warm up detector
      final dummyDetInput = Float32List(1 * 3 * _detectorInputSize * _detectorInputSize);
      final detTensor = OrtValueTensor.createTensorWithDataList(dummyDetInput, [1, 3, _detectorInputSize, _detectorInputSize]);
      final detRunOptions = OrtRunOptions();
      try {
        _detectorSession!.run(
          detRunOptions,
          {_detectorSession!.inputNames.first: detTensor},
        );
      } finally {
        detRunOptions.release();
      }

      // Warm up recognizer
      const recH = 32;
      const recW = 320;
      final dummyRecInput = Float32List(1 * 3 * recH * recW);
      final recTensor = OrtValueTensor.createTensorWithDataList(dummyRecInput, [1, 3, recH, recW]);
      final recRunOptions = OrtRunOptions();
      try {
        _recognizerSession!.run(
          recRunOptions,
          {_recognizerSession!.inputNames.first: recTensor},
        );
      } finally {
        recRunOptions.release();
      }

      _logger.info('PaddleOCR models warmed up');
    } catch (e) {
      _logger.warning('PaddleOCR warm-up failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    _detectorSession?.release();
    _detectorSession = null;
    _recognizerSession?.release();
    _recognizerSession = null;
    _initialized = false;
    _initGuard.reset();
  }
}

/// Text box with confidence for NMS.
class _TextBox {
  const _TextBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
  });

  final double x1, y1, x2, y2;
  final double confidence;
}