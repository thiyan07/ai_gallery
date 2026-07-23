/// OCR text extraction result.
class OcrResult {
  final String id;
  final String photoId;
  final String text;
  final double confidence;
  final double? boundingBoxLeft;
  final double? boundingBoxTop;
  final double? boundingBoxWidth;
  final double? boundingBoxHeight;

  const OcrResult({
    required this.id,
    required this.photoId,
    required this.text,
    required this.confidence,
    this.boundingBoxLeft,
    this.boundingBoxTop,
    this.boundingBoxWidth,
    this.boundingBoxHeight,
  });

  OcrResult copyWith({
    String? id,
    String? photoId,
    String? text,
    double? confidence,
    double? boundingBoxLeft,
    double? boundingBoxTop,
    double? boundingBoxWidth,
    double? boundingBoxHeight,
  }) {
    return OcrResult(
      id: id ?? this.id,
      photoId: photoId ?? this.photoId,
      text: text ?? this.text,
      confidence: confidence ?? this.confidence,
      boundingBoxLeft: boundingBoxLeft ?? this.boundingBoxLeft,
      boundingBoxTop: boundingBoxTop ?? this.boundingBoxTop,
      boundingBoxWidth: boundingBoxWidth ?? this.boundingBoxWidth,
      boundingBoxHeight: boundingBoxHeight ?? this.boundingBoxHeight,
    );
  }
}

/// Database record for OCR text storage.
class OcrRecord {
  final String id;
  final String photoId;
  final String text;
  final double confidence;
  final double? boundingBoxLeft;
  final double? boundingBoxTop;
  final double? boundingBoxWidth;
  final double? boundingBoxHeight;

  const OcrRecord({
    required this.id,
    required this.photoId,
    required this.text,
    required this.confidence,
    this.boundingBoxLeft,
    this.boundingBoxTop,
    this.boundingBoxWidth,
    this.boundingBoxHeight,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'photo_id': photoId,
      'text': text,
      'confidence': confidence,
      'bounding_box_left': boundingBoxLeft,
      'bounding_box_top': boundingBoxTop,
      'bounding_box_width': boundingBoxWidth,
      'bounding_box_height': boundingBoxHeight,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  factory OcrRecord.fromMap(Map<String, dynamic> map) {
    return OcrRecord(
      id: map['id'] as String,
      photoId: map['photo_id'] as String,
      text: map['text'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      boundingBoxLeft: map['bounding_box_left'] != null
          ? (map['bounding_box_left'] as num).toDouble()
          : null,
      boundingBoxTop: map['bounding_box_top'] != null
          ? (map['bounding_box_top'] as num).toDouble()
          : null,
      boundingBoxWidth: map['bounding_box_width'] != null
          ? (map['bounding_box_width'] as num).toDouble()
          : null,
      boundingBoxHeight: map['bounding_box_height'] != null
          ? (map['bounding_box_height'] as num).toDouble()
          : null,
    );
  }
}