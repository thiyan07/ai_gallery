import 'knowledge_entity.dart';

/// Types of relationships between entities in the knowledge graph.
///
/// Naming convention: `sourceType_action_targetType`.
/// All relationships are directional for traversal, but many are logically
/// bidirectional (e.g., `media_includes_person` ↔ `person_appears_in_media`).
enum KnowledgeRelationType {
  // Media ↔ People
  mediaIncludesPerson,
  personAppearsInMedia,

  // Media ↔ Places
  mediaAtPlace,
  placeContainsMedia,

  // Media ↔ Events
  mediaBelongsToEvent,
  eventContainsMedia,

  // Media ↔ Objects
  mediaShowsObject,
  objectAppearsInMedia,

  // Media ↔ Memory
  mediaBelongsToMemory,
  memoryContainsMedia,

  // People ↔ People
  peopleCoOccurs,

  // People ↔ Events
  personAttendedEvent,
  eventAttendedByPerson,

  // People ↔ Places
  personVisitedPlace,
  placeVisitedByPerson,

  // People ↔ Memory
  personInMemory,
  memoryContainsPerson,

  // Events ↔ Events
  eventsTemporal,

  // Events ↔ Places
  eventAtPlace,
  placeHostedEvent,

  // Events ↔ Memory
  eventInMemory,
  memoryContainsEvent,

  // Memory ↔ People (beyond personInMemory)
  memoryInvolvesPeople,
}

extension KnowledgeRelationTypeExtension on KnowledgeRelationType {
  /// Returns the source entity type for this relation.
  KnowledgeEntityType get sourceType {
    switch (this) {
      case KnowledgeRelationType.mediaIncludesPerson:
      case KnowledgeRelationType.mediaAtPlace:
      case KnowledgeRelationType.mediaBelongsToEvent:
      case KnowledgeRelationType.mediaShowsObject:
      case KnowledgeRelationType.mediaBelongsToMemory:
        return KnowledgeEntityType.media;
      case KnowledgeRelationType.personAppearsInMedia:
      case KnowledgeRelationType.peopleCoOccurs:
      case KnowledgeRelationType.personAttendedEvent:
      case KnowledgeRelationType.personVisitedPlace:
      case KnowledgeRelationType.personInMemory:
        return KnowledgeEntityType.person;
      case KnowledgeRelationType.placeContainsMedia:
      case KnowledgeRelationType.placeVisitedByPerson:
      case KnowledgeRelationType.placeHostedEvent:
        return KnowledgeEntityType.place;
      case KnowledgeRelationType.eventContainsMedia:
      case KnowledgeRelationType.eventAttendedByPerson:
      case KnowledgeRelationType.eventAtPlace:
      case KnowledgeRelationType.eventInMemory:
        return KnowledgeEntityType.event;
      case KnowledgeRelationType.objectAppearsInMedia:
        return KnowledgeEntityType.object;
      case KnowledgeRelationType.memoryContainsMedia:
      case KnowledgeRelationType.memoryContainsPerson:
      case KnowledgeRelationType.memoryContainsEvent:
      case KnowledgeRelationType.memoryInvolvesPeople:
        return KnowledgeEntityType.memory;
      case KnowledgeRelationType.eventsTemporal:
        return KnowledgeEntityType.event;
    }
  }

  /// Returns the target entity type for this relation.
  KnowledgeEntityType get targetType {
    switch (this) {
      case KnowledgeRelationType.mediaIncludesPerson:
      case KnowledgeRelationType.personAppearsInMedia:
        return KnowledgeEntityType.person;
      case KnowledgeRelationType.mediaAtPlace:
      case KnowledgeRelationType.placeContainsMedia:
        return KnowledgeEntityType.place;
      case KnowledgeRelationType.mediaBelongsToEvent:
      case KnowledgeRelationType.eventContainsMedia:
        return KnowledgeEntityType.event;
      case KnowledgeRelationType.mediaShowsObject:
      case KnowledgeRelationType.objectAppearsInMedia:
        return KnowledgeEntityType.object;
      case KnowledgeRelationType.mediaBelongsToMemory:
      case KnowledgeRelationType.memoryContainsMedia:
        return KnowledgeEntityType.memory;
      case KnowledgeRelationType.peopleCoOccurs:
        return KnowledgeEntityType.person;
      case KnowledgeRelationType.personAttendedEvent:
      case KnowledgeRelationType.eventAttendedByPerson:
        return KnowledgeEntityType.event;
      case KnowledgeRelationType.personVisitedPlace:
      case KnowledgeRelationType.placeVisitedByPerson:
        return KnowledgeEntityType.place;
      case KnowledgeRelationType.personInMemory:
      case KnowledgeRelationType.memoryContainsPerson:
        return KnowledgeEntityType.memory;
      case KnowledgeRelationType.eventAtPlace:
      case KnowledgeRelationType.placeHostedEvent:
        return KnowledgeEntityType.place;
      case KnowledgeRelationType.eventInMemory:
      case KnowledgeRelationType.memoryContainsEvent:
        return KnowledgeEntityType.memory;
      case KnowledgeRelationType.memoryInvolvesPeople:
        return KnowledgeEntityType.person;
      case KnowledgeRelationType.eventsTemporal:
        return KnowledgeEntityType.event;
    }
  }

  String get value {
    switch (this) {
      case KnowledgeRelationType.mediaIncludesPerson:
        return 'media_includes_person';
      case KnowledgeRelationType.personAppearsInMedia:
        return 'person_appears_in_media';
      case KnowledgeRelationType.mediaAtPlace:
        return 'media_at_place';
      case KnowledgeRelationType.placeContainsMedia:
        return 'place_contains_media';
      case KnowledgeRelationType.mediaBelongsToEvent:
        return 'media_belongs_to_event';
      case KnowledgeRelationType.eventContainsMedia:
        return 'event_contains_media';
      case KnowledgeRelationType.mediaShowsObject:
        return 'media_shows_object';
      case KnowledgeRelationType.objectAppearsInMedia:
        return 'object_appears_in_media';
      case KnowledgeRelationType.mediaBelongsToMemory:
        return 'media_belongs_to_memory';
      case KnowledgeRelationType.memoryContainsMedia:
        return 'memory_contains_media';
      case KnowledgeRelationType.peopleCoOccurs:
        return 'people_co_occurs';
      case KnowledgeRelationType.personAttendedEvent:
        return 'person_attended_event';
      case KnowledgeRelationType.eventAttendedByPerson:
        return 'event_attended_by_person';
      case KnowledgeRelationType.personVisitedPlace:
        return 'person_visited_place';
      case KnowledgeRelationType.placeVisitedByPerson:
        return 'place_visited_by_person';
      case KnowledgeRelationType.personInMemory:
        return 'person_in_memory';
      case KnowledgeRelationType.memoryContainsPerson:
        return 'memory_contains_person';
      case KnowledgeRelationType.eventAtPlace:
        return 'event_at_place';
      case KnowledgeRelationType.placeHostedEvent:
        return 'place_hosted_event';
      case KnowledgeRelationType.eventInMemory:
        return 'event_in_memory';
      case KnowledgeRelationType.memoryContainsEvent:
        return 'memory_contains_event';
      case KnowledgeRelationType.memoryInvolvesPeople:
        return 'memory_involves_people';
      case KnowledgeRelationType.eventsTemporal:
        return 'events_temporal';
    }
  }

  static KnowledgeRelationType fromValue(String value) {
    return KnowledgeRelationType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => KnowledgeRelationType.mediaIncludesPerson,
    );
  }
}

/// Evidence sources that can generate a relationship.
enum EvidenceSource {
  faceDetection,
  objectDetection,
  ocr,
  eventClustering,
  memoryGeneration,
  embeddingSimilarity,
  userAction,
  metadataExtraction,
  inference,
}

extension EvidenceSourceExtension on EvidenceSource {
  String get value {
    switch (this) {
      case EvidenceSource.faceDetection:
        return 'face_detection';
      case EvidenceSource.objectDetection:
        return 'object_detection';
      case EvidenceSource.ocr:
        return 'ocr';
      case EvidenceSource.eventClustering:
        return 'event_clustering';
      case EvidenceSource.memoryGeneration:
        return 'memory_generation';
      case EvidenceSource.embeddingSimilarity:
        return 'embedding_similarity';
      case EvidenceSource.userAction:
        return 'user_action';
      case EvidenceSource.metadataExtraction:
        return 'metadata_extraction';
      case EvidenceSource.inference:
        return 'inference';
    }
  }

  static EvidenceSource fromValue(String value) {
    return EvidenceSource.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EvidenceSource.inference,
    );
  }
}

/// An edge in the knowledge graph connecting two entities.
///
/// Each relationship has:
/// - A direction (sourceId → targetId)
/// - A type defining the semantic meaning
/// - Evidence metadata: source, confidence, analysis version
/// - Deduplication via composite key (relationType + sourceId + targetId)
class KnowledgeRelationship {
  final int? id;
  final KnowledgeRelationType relationType;
  final String sourceEntityId;
  final String targetEntityId;
  final double confidence;
  final EvidenceSource evidenceSource;
  final String? evidenceDetail;
  final String analysisVersion;
  final int weight;
  final DateTime createdAt;
  final DateTime updatedAt;

  const KnowledgeRelationship({
    this.id,
    required this.relationType,
    required this.sourceEntityId,
    required this.targetEntityId,
    this.confidence = 1.0,
    required this.evidenceSource,
    this.evidenceDetail,
    this.analysisVersion = '1.0',
    this.weight = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  KnowledgeRelationship copyWith({
    int? id,
    KnowledgeRelationType? relationType,
    String? sourceEntityId,
    String? targetEntityId,
    double? confidence,
    EvidenceSource? evidenceSource,
    String? evidenceDetail,
    String? analysisVersion,
    int? weight,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KnowledgeRelationship(
      id: id ?? this.id,
      relationType: relationType ?? this.relationType,
      sourceEntityId: sourceEntityId ?? this.sourceEntityId,
      targetEntityId: targetEntityId ?? this.targetEntityId,
      confidence: confidence ?? this.confidence,
      evidenceSource: evidenceSource ?? this.evidenceSource,
      evidenceDetail: evidenceDetail ?? this.evidenceDetail,
      analysisVersion: analysisVersion ?? this.analysisVersion,
      weight: weight ?? this.weight,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Composite key for deduplication.
  String get compositeKey =>
      '${relationType.value}:${sourceEntityId}:${targetEntityId}';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'relation_type': relationType.value,
        'source_entity_id': sourceEntityId,
        'target_entity_id': targetEntityId,
        'confidence': confidence,
        'evidence_source': evidenceSource.value,
        'evidence_detail': evidenceDetail,
        'analysis_version': analysisVersion,
        'weight': weight,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory KnowledgeRelationship.fromMap(Map<String, Object?> row) =>
      KnowledgeRelationship(
        id: row['id'] as int?,
        relationType: KnowledgeRelationTypeExtension.fromValue(
          row['relation_type'] as String,
        ),
        sourceEntityId: row['source_entity_id'] as String,
        targetEntityId: row['target_entity_id'] as String,
        confidence: (row['confidence'] as num?)?.toDouble() ?? 1.0,
        evidenceSource: EvidenceSourceExtension.fromValue(
          row['evidence_source'] as String,
        ),
        evidenceDetail: row['evidence_detail'] as String?,
        analysisVersion: row['analysis_version'] as String? ?? '1.0',
        weight: row['weight'] as int? ?? 1,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KnowledgeRelationship &&
          runtimeType == other.runtimeType &&
          relationType == other.relationType &&
          sourceEntityId == other.sourceEntityId &&
          targetEntityId == other.targetEntityId;

  @override
  int get hashCode => compositeKey.hashCode;

  @override
  String toString() =>
      'KnowledgeRelation(${relationType.value}: $sourceEntityId → $targetEntityId, '
      'conf=$confidence, src=${evidenceSource.value})';
}
