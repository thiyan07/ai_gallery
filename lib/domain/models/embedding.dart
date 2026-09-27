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

  /// YOLO label of the embedded object crop, or null for whole-photo rows.
  final String? regionLabel;

  const Embedding({
    required this.id,
    required this.photoId,
    required this.model,
    required this.vector,
    required this.createdAt,
    this.regionLabel,
  });

  /// Whether this is a per-region (object crop) embedding.
  bool get isRegion => regionLabel != null;

  Embedding copyWith({
    String? id,
    String? photoId,
    String? model,
    Float32List? vector,
    DateTime? createdAt,
    String? regionLabel,
  }) {
    return Embedding(
      id: id ?? this.id,
      photoId: photoId ?? this.photoId,
      model: model ?? this.model,
      vector: vector ?? this.vector,
      createdAt: createdAt ?? this.createdAt,
      regionLabel: regionLabel ?? this.regionLabel,
    );
  }
}

/// Database record for embedding storage.
///
/// A photo has one *global* embedding (regionLabel == null) plus zero or more
/// *region* embeddings, one per prominent detected object crop. Region rows let
/// semantic search match small/background objects in complex scenes that the
/// single global vector averages away.
class EmbeddingRecord {
  EmbeddingRecord({
    required this.id,
    required this.photoId,
    required this.vector,
    required this.modelId,
    required this.dimensions,
    this.regionLabel,
    this.regionBboxLeft,
    this.regionBboxTop,
    this.regionBboxWidth,
    this.regionBboxHeight,
  });

  final String id;
  final String photoId;
  final Float32List vector;
  final String modelId;
  final int dimensions;

  /// YOLO label of the embedded crop (null for the whole-photo embedding).
  final String? regionLabel;

  /// Normalized [0,1] bounding box of the embedded crop (null for global).
  final double? regionBboxLeft;
  final double? regionBboxTop;
  final double? regionBboxWidth;
  final double? regionBboxHeight;

  /// Whether this is a per-region (object crop) embedding.
  bool get isRegion => regionLabel != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'photo_id': photoId,
      'vector': vector.buffer.asUint8List(),
      'model': modelId,
      'dimensions': dimensions,
      'region_label': regionLabel,
      'region_bbox_left': regionBboxLeft,
      'region_bbox_top': regionBboxTop,
      'region_bbox_width': regionBboxWidth,
      'region_bbox_height': regionBboxHeight,
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
      regionLabel: map['region_label'] as String?,
      regionBboxLeft: (map['region_bbox_left'] as num?)?.toDouble(),
      regionBboxTop: (map['region_bbox_top'] as num?)?.toDouble(),
      regionBboxWidth: (map['region_bbox_width'] as num?)?.toDouble(),
      regionBboxHeight: (map['region_bbox_height'] as num?)?.toDouble(),
    );
  }
}