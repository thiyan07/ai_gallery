/// Domain model representing OCR-extracted text from a photo.
class OCRText {
  /// Unique identifier for this OCR record.
  final String id;

  /// ID of the photo the text was extracted from.
  final String photoId;

  /// Extracted text content.
  final String text;

  /// Confidence score from 0.0 to 1.0.
  final double confidence;

  /// Optional bounding box left coordinate (normalized 0–1).
  final double? boundingBoxLeft;

  /// Optional bounding box top coordinate (normalized 0–1).
  final double? boundingBoxTop;

  /// Optional bounding box width (normalized 0–1).
  final double? boundingBoxWidth;

  /// Optional bounding box height (normalized 0–1).
  final double? boundingBoxHeight;

  const OCRText({
    required this.id,
    required this.photoId,
    required this.text,
    required this.confidence,
    this.boundingBoxLeft,
    this.boundingBoxTop,
    this.boundingBoxWidth,
    this.boundingBoxHeight,
  });

  OCRText copyWith({
    String? id,
    String? photoId,
    String? text,
    double? confidence,
    double? boundingBoxLeft,
    double? boundingBoxTop,
    double? boundingBoxWidth,
    double? boundingBoxHeight,
  }) {
    return OCRText(
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
