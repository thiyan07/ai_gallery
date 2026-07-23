/// Object detection result.
class ObjectDetection {
  const ObjectDetection({
    required this.label,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String label;
  final double confidence;
  final double x, y, width, height; // Normalized [0,1]
}

/// Database record for object detection storage.
class ObjectTagRecord {
  ObjectTagRecord({
    required this.id,
    required this.photoId,
    required this.label,
    required this.confidence,
    required this.boundingBoxLeft,
    required this.boundingBoxTop,
    required this.boundingBoxWidth,
    required this.boundingBoxHeight,
  });

  final String id;
  final String photoId;
  final String label;
  final double confidence;
  final double boundingBoxLeft;
  final double boundingBoxTop;
  final double boundingBoxWidth;
  final double boundingBoxHeight;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'photo_id': photoId,
      'label': label,
      'confidence': confidence,
      'bounding_box_left': boundingBoxLeft,
      'bounding_box_top': boundingBoxTop,
      'bounding_box_width': boundingBoxWidth,
      'bounding_box_height': boundingBoxHeight,
    };
  }

  factory ObjectTagRecord.fromMap(Map<String, dynamic> map) {
    return ObjectTagRecord(
      id: map['id'] as String,
      photoId: map['photo_id'] as String,
      label: map['label'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      boundingBoxLeft: (map['bounding_box_left'] as num).toDouble(),
      boundingBoxTop: (map['bounding_box_top'] as num).toDouble(),
      boundingBoxWidth: (map['bounding_box_width'] as num).toDouble(),
      boundingBoxHeight: (map['bounding_box_height'] as num).toDouble(),
    );
  }
}