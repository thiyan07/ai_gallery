/// Face detection result with normalized coordinates [0, 1].
class FaceDetection {
  const FaceDetection({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  final double x, y, width, height;
  final double confidence;
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
  });

  final String id;
  final String photoId;
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;

  Map<String, dynamic> toMap() => {
        'id': id,
        'photo_id': photoId,
        'bounding_box_left': x,
        'bounding_box_top': y,
        'bounding_box_width': width,
        'bounding_box_height': height,
        'confidence': confidence,
        'label': null,
        'embedding': null,
      };

  factory FaceDetectionRecord.fromMap(Map<String, dynamic> map) {
    return FaceDetectionRecord(
      id: map['id'] as String,
      photoId: map['photo_id'] as String,
      x: (map['bounding_box_left'] as num).toDouble(),
      y: (map['bounding_box_top'] as num).toDouble(),
      width: (map['bounding_box_width'] as num).toDouble(),
      height: (map['bounding_box_height'] as num).toDouble(),
      confidence: (map['confidence'] as num).toDouble(),
    );
  }
}