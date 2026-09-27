/// Types of entities in the personal media knowledge graph.
enum KnowledgeEntityType {
  media,
  person,
  place,
  event,
  object,
  memory,
}

extension KnowledgeEntityTypeExtension on KnowledgeEntityType {
  String get value {
    switch (this) {
      case KnowledgeEntityType.media:
        return 'media';
      case KnowledgeEntityType.person:
        return 'person';
      case KnowledgeEntityType.place:
        return 'place';
      case KnowledgeEntityType.event:
        return 'event';
      case KnowledgeEntityType.object:
        return 'object';
      case KnowledgeEntityType.memory:
        return 'memory';
    }
  }

  static KnowledgeEntityType fromValue(String value) {
    return KnowledgeEntityType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => KnowledgeEntityType.media,
    );
  }
}

/// A node in the personal media knowledge graph.
///
/// Every entity is identified by a composite key (type + externalId).
/// The externalId references the primary key in the originating table:
///   - media    → photo_metadata.photo_id
///   - person   → people.person_id
///   - place    → generated place key (lat_lng hash)
///   - event    → photo_events.event_id
///   - object   → object_tags.label
///   - memory   → memories.memory_id
class KnowledgeEntity {
  final int? id;
  final KnowledgeEntityType type;
  final String externalId;
  final String? displayName;
  final int occurrenceCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const KnowledgeEntity({
    this.id,
    required this.type,
    required this.externalId,
    this.displayName,
    this.occurrenceCount = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  KnowledgeEntity copyWith({
    int? id,
    KnowledgeEntityType? type,
    String? externalId,
    String? displayName,
    int? occurrenceCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KnowledgeEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      externalId: externalId ?? this.externalId,
      displayName: displayName ?? this.displayName,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Composite key used for deduplication.
  String get compositeKey => '${type.value}:$externalId';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type.value,
        'external_id': externalId,
        'display_name': displayName,
        'occurrence_count': occurrenceCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory KnowledgeEntity.fromMap(Map<String, Object?> row) =>
      KnowledgeEntity(
        id: row['id'] as int?,
        type: KnowledgeEntityTypeExtension.fromValue(row['type'] as String),
        externalId: row['external_id'] as String,
        displayName: row['display_name'] as String?,
        occurrenceCount: row['occurrence_count'] as int? ?? 1,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KnowledgeEntity &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          externalId == other.externalId;

  @override
  int get hashCode => compositeKey.hashCode;

  @override
  String toString() => 'KnowledgeEntity($compositeKey, "$displayName")';
}
