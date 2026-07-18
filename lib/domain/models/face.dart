/// Domain model representing a detected face in a photo.
class Face {
  /// Unique identifier for this face record.
  final String id;

  /// ID of the photo this face was detected in.
  final String photoId;

  /// Bounding box left coordinate (normalized 0–1).
  final double boundingBoxLeft;

  /// Bounding box top coordinate (normalized 0–1).
  final double boundingBoxTop;

  /// Bounding box width (normalized 0–1).
  final double boundingBoxWidth;

  /// Bounding box height (normalized 0–1).
  final double boundingBoxHeight;

  /// Optional person/cluster label assigned to this face.
  final String? label;

  /// Optional embedding vector for similarity search.
  final List<double>? embedding;

  const Face({
    required this.id,
    required this.photoId,
    required this.boundingBoxLeft,
    required this.boundingBoxTop,
    required this.boundingBoxWidth,
    required this.boundingBoxHeight,
    this.label,
    this.embedding,
  });

  Face copyWith({
    String? id,
    String? photoId,
    double? boundingBoxLeft,
    double? boundingBoxTop,
    double? boundingBoxWidth,
    double? boundingBoxHeight,
    String? label,
    List<double>? embedding,
  }) {
    return Face(
      id: id ?? this.id,
      photoId: photoId ?? this.photoId,
      boundingBoxLeft: boundingBoxLeft ?? this.boundingBoxLeft,
      boundingBoxTop: boundingBoxTop ?? this.boundingBoxTop,
      boundingBoxWidth: boundingBoxWidth ?? this.boundingBoxWidth,
      boundingBoxHeight: boundingBoxHeight ?? this.boundingBoxHeight,
      label: label ?? this.label,
      embedding: embedding ?? this.embedding,
    );
  }
}
