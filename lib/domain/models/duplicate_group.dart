/// Represents a group of duplicate or near-duplicate photos.
///
/// Groups are created by the duplicate detection engine and stored
/// persistently. The system never auto-deletes — the user decides
/// which copies to keep.
class DuplicateGroup {
  final String groupId;
  final List<String> photoIds;
  final DuplicateType type;
  final double similarity;
  final double confidence;
  final String? recommendedKeepId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DuplicateGroup({
    required this.groupId,
    required this.photoIds,
    required this.type,
    required this.similarity,
    required this.confidence,
    this.recommendedKeepId,
    required this.createdAt,
    required this.updatedAt,
  });

  int get count => photoIds.length;

  bool get hasRecommendation => recommendedKeepId != null;

  DuplicateGroup copyWith({
    String? groupId,
    List<String>? photoIds,
    DuplicateType? type,
    double? similarity,
    double? confidence,
    String? recommendedKeepId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DuplicateGroup(
      groupId: groupId ?? this.groupId,
      photoIds: photoIds ?? this.photoIds,
      type: type ?? this.type,
      similarity: similarity ?? this.similarity,
      confidence: confidence ?? this.confidence,
      recommendedKeepId: recommendedKeepId ?? this.recommendedKeepId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'group_id': groupId,
        'photo_ids': photoIds.join(','),
        'type': type.index,
        'similarity': similarity,
        'confidence': confidence,
        'recommended_keep_id': recommendedKeepId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory DuplicateGroup.fromMap(Map<String, Object?> row) => DuplicateGroup(
        groupId: row['group_id'] as String,
        photoIds: (row['photo_ids'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
        type: DuplicateType.values[row['type'] as int],
        similarity: row['similarity'] as double,
        confidence: row['confidence'] as double,
        recommendedKeepId: row['recommended_keep_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DuplicateGroup &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId;

  @override
  int get hashCode => groupId.hashCode;
}

/// Type of duplicate relationship.
enum DuplicateType {
  /// Byte-identical files.
  exact,

  /// Visually identical but possibly different compression/format.
  nearDuplicate,

  /// Slightly different (burst shots, edits, crops).
  similar,
}
