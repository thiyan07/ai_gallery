/// Object detection result with full bounding box and metadata.
class ObjectDetectionResult {
  const ObjectDetectionResult({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.inferenceTimeMs,
  });

  /// List of detected objects with labels, confidence scores, and bounding boxes.
  final List<DetectedObject> detections;

  /// Original image width in pixels.
  final int imageWidth;

  /// Original image height in pixels.
  final int imageHeight;

  /// Inference time in milliseconds.
  final int inferenceTimeMs;

  /// Get unique labels from detections.
  Set<String> get uniqueLabels => detections.map((d) => d.label).toSet();

  /// Get detections for a specific label.
  List<DetectedObject> getDetectionsForLabel(String label) =>
      detections.where((d) => d.label.toLowerCase() == label.toLowerCase()).toList();

  /// Get highest confidence detection for a label.
  DetectedObject? getBestDetection(String label) {
    final filtered = getDetectionsForLabel(label);
    if (filtered.isEmpty) return null;
    filtered.sort((a, b) => b.confidence.compareTo(a.confidence));
    return filtered.first;
  }
}

/// A single detected object with bounding box and confidence.
class DetectedObject {
  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    this.classIndex,
  });

  /// Class label (e.g., "person", "car", "dog").
  final String label;

  /// Confidence score from 0.0 to 1.0.
  final double confidence;

  /// Bounding box in normalized coordinates [centerX, centerY, width, height]
  /// where all values are in range [0, 1] relative to image dimensions.
  final List<double> boundingBox;

  /// Class index in the model's label list (optional).
  final int? classIndex;

  /// Convert to absolute pixel coordinates for the given image dimensions.
  Rect toAbsolute(int imageWidth, int imageHeight) {
    final cx = boundingBox[0] * imageWidth;
    final cy = boundingBox[1] * imageHeight;
    final w = boundingBox[2] * imageWidth;
    final h = boundingBox[3] * imageHeight;
    return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  }

  /// Bounding box in [left, top, right, bottom] format normalized to [0,1].
  List<double> get boundingBoxLTRB {
    final cx = boundingBox[0];
    final cy = boundingBox[1];
    final w = boundingBox[2];
    final h = boundingBox[3];
    return [
      (cx - w / 2).clamp(0.0, 1.0),
      (cy - h / 2).clamp(0.0, 1.0),
      (cx + w / 2).clamp(0.0, 1.0),
      (cy + h / 2).clamp(0.0, 1.0),
    ];
  }
}

/// Simple Rect class for bounding boxes (to avoid dart:ui dependency).
class Rect {
  Rect.fromCenter({required this.center, required this.width, required this.height})
      : left = center.dx - width / 2,
        top = center.dy - height / 2,
        right = center.dx + width / 2,
        bottom = center.dy + height / 2;

  final Offset center;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double width;
  final double height;
}

/// Simple Offset class for coordinates.
class Offset {
  const Offset(this.dx, this.dy);
  final double dx;
  final double dy;
}