import 'dart:typed_data';

import '../../domain/models/face_detection.dart';

/// Abstract provider for face detection.
abstract class FaceDetectionProvider {
  /// Unique identifier for this provider.
  String get id;

  /// Human-readable name for this provider.
  String get name;

  /// Whether this provider is available (e.g., model loaded).
  Future<bool> get isAvailable;

  /// Detect faces in the given image bytes.
  ///
  /// Returns a list of FaceDetection objects containing bounding boxes,
  /// keypoints, and confidence scores.
  Future<List<FaceDetection>> detectFaces(Uint8List imageBytes);

  /// Initialize the provider (load model).
  Future<void> initialize();

  /// Warm up the model (run dummy inference).
  Future<void> warmUp();

  /// Dispose resources.
  Future<void> dispose();
}

/// Fallback provider that returns empty results (when no model is available).
class NullFaceDetectionProvider implements FaceDetectionProvider {
  @override
  String get id => 'null';

  @override
  String get name => 'None (Disabled)';

  @override
  Future<bool> get isAvailable => Future.value(true);

  @override
  Future<List<FaceDetection>> detectFaces(Uint8List imageBytes) async =>
      <FaceDetection>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> dispose() async {}
}