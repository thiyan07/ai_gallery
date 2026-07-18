/// Domain model representing a vector embedding for semantic search.
class Embedding {
  /// Unique identifier for this embedding record.
  final String id;

  /// ID of the photo this embedding was generated from.
  final String photoId;

  /// Model used to generate the embedding (e.g. "clip-vit-b32").
  final String model;

  /// Vector values for similarity search.
  final List<double> vector;

  /// When this embedding was created.
  final DateTime createdAt;

  const Embedding({
    required this.id,
    required this.photoId,
    required this.model,
    required this.vector,
    required this.createdAt,
  });

  Embedding copyWith({
    String? id,
    String? photoId,
    String? model,
    List<double>? vector,
    DateTime? createdAt,
  }) {
    return Embedding(
      id: id ?? this.id,
      photoId: photoId ?? this.photoId,
      model: model ?? this.model,
      vector: vector ?? this.vector,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
