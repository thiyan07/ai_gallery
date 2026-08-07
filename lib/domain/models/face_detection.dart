import 'dart:typed_data';

/// Face detection result with normalized coordinates [0, 1].
class FaceDetection {
  const FaceDetection({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    this.keypoints = const [],
    this.label,
    this.embedding,
  });

  final double x, y, width, height;
  final double confidence;

  /// Face keypoints (eyes, nose, mouth, ears) in normalized coordinates [0, 1].
  final List<FaceKeypoint> keypoints;

  /// Optional person label (from clustering).
  final String? label;

  /// Optional face embedding vector for recognition.
  final Float32List? embedding;
}

/// Face keypoint (eye, nose, mouth, etc.) with normalized coordinates [0, 1].
class FaceKeypoint {
  const FaceKeypoint({
    required this.name,
    required this.x,
    required this.y,
  });

  final String name;
  final double x, y; // Normalized [0, 1]
}

/// Face detection record for database storage.
class FaceDetectionRecord {
  const FaceDetectionRecord({
    required this.id,
    required this.photoId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    this.label,
    this.embedding,
  });

  final String id;
  final String photoId;
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;
  final String? label;
  final Float32List? embedding;

  Map<String, dynamic> toMap() => {
        'id': id,
        'photo_id': photoId,
        'bounding_box_left': x,
        'bounding_box_top': y,
        'bounding_box_width': width,
        'bounding_box_height': height,
        'confidence': confidence,
        'label': label,
        'embedding': embedding?.buffer.asUint8List(),
      };

  factory FaceDetectionRecord.fromMap(Map<String, dynamic> map) {
    final embeddingBytes = map['embedding'] as Uint8List?;
    return FaceDetectionRecord(
      id: map['id'] as String,
      photoId: map['photo_id'] as String,
      x: (map['bounding_box_left'] as num).toDouble(),
      y: (map['bounding_box_top'] as num).toDouble(),
      width: (map['bounding_box_width'] as num).toDouble(),
      height: (map['bounding_box_height'] as num).toDouble(),
      confidence: (map['confidence'] as num).toDouble(),
      label: map['label'] as String?,
      embedding: embeddingBytes != null
          ? Float32List.fromList(embeddingBytes.buffer.asFloat32List())
          : null,
    );
  }
}