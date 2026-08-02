import 'dart:typed_data';

import '../../domain/models/object_detection.dart';
import '../../domain/models/object_detection_model.dart';

/// Abstract provider for object detection.
abstract class ObjectDetectionProvider {
  /// Unique identifier for this provider.
  String get id;

  /// Human-readable name for this provider.
  String get name;

  /// Whether this provider is available (e.g., model loaded).
  Future<bool> get isAvailable;

  /// Detect objects in the given image bytes.
  ///
  /// Returns ObjectDetectionResult containing all detections with metadata.
  Future<ObjectDetectionResult> detectObjects(Uint8List imageBytes);

  /// Get the list of class labels this model can detect.
  List<String> get labels;

  /// Initialize the provider (load model).
  Future<void> initialize();

  /// Warm up the model (run dummy inference).
  Future<void> warmUp();

  /// Dispose resources.
  Future<void> dispose();
}

/// Fallback provider that returns empty results (when no model is available).
class NullObjectDetectionProvider implements ObjectDetectionProvider {
  @override
  String get id => 'null';

  @override
  String get name => 'None (Disabled)';

  @override
  Future<bool> get isAvailable => Future.value(true);

  @override
  List<String> get labels => [];

  @override
  Future<ObjectDetectionResult> detectObjects(Uint8List imageBytes) async =>
      ObjectDetectionResult(
        detections: [],
        imageWidth: 0,
        imageHeight: 0,
        inferenceTimeMs: 0,
      );

  @override
  Future<void> initialize() async {}

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> dispose() async {}
}