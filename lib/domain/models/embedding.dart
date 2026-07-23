import 'dart:typed_data';

/// Domain model representing a vector embedding for semantic search.
class Embedding {
  /// Unique identifier for this embedding record.
  final String id;

  /// ID of the photo this embedding was generated from.
  final String photoId;

  /// Model used to generate the embedding (e.g. "clip-vit-b32").
  final String model;

  /// Vector values for similarity search.
  final Float32List vector;

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
    Float32List? vector,
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

/// Database record for embedding storage.
class EmbeddingRecord {
  EmbeddingRecord({
    required this.id,
    required this.photoId,
    required this.vector,
    required this.modelId,
    required this.dimensions,
  });

  final String id;
  final String photoId;
  final Float32List vector;
  final String modelId;
  final int dimensions;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'photo_id': photoId,
      'vector': vector.buffer.asUint8List(),
      'model': modelId,
      'dimensions': dimensions,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  factory EmbeddingRecord.fromMap(Map<String, dynamic> map) {
    final vectorBytes = map['vector'] as Uint8List;
    return EmbeddingRecord(
      id: map['id'] as String,
      photoId: map['photo_id'] as String,
      vector: Float32List.fromList(vectorBytes.buffer.asFloat32List()),
      modelId: map['model'] as String,
      dimensions: map['dimensions'] as int,
    );
  }
}