/// Domain model representing an AI-detected object label on a photo.
class ObjectTag {
  /// Unique identifier for this tag record.
  final String id;

  /// ID of the photo this tag belongs to.
  final String photoId;

  /// Human-readable label (e.g. "dog", "car").
  final String label;

  /// Confidence score from 0.0 to 1.0.
  final double confidence;

  const ObjectTag({
    required this.id,
    required this.photoId,
    required this.label,
    required this.confidence,
  });

  ObjectTag copyWith({
    String? id,
    String? photoId,
    String? label,
    double? confidence,
  }) {
    return ObjectTag(
      id: id ?? this.id,
      photoId: photoId ?? this.photoId,
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
    );
  }
}
