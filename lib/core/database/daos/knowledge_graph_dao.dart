import 'package:sqflite/sqflite.dart';

import '../../../domain/models/knowledge_entity.dart';
import '../../../domain/models/knowledge_relationship.dart';

/// Data access object for the personal media knowledge graph.
///
/// All operations use composite-key upserts to ensure idempotency.
/// The graph is append-only during indexing; stale edges are pruned
/// when photos are deleted.
class KnowledgeGraphDao {
  KnowledgeGraphDao(this._db);

  final Database _db;

  // ── Entity operations ──────────────────────────────────────────────

  /// Upserts a single entity. Returns the row id.
  Future<int> upsertEntity(KnowledgeEntity entity) async {
    final existing = await _findEntity(entity.type, entity.externalId);
    if (existing != null) {
      await _db.update(
        'knowledge_graph_entities',
        {
          'display_name': entity.displayName ?? existing.displayName,
          'occurrence_count': entity.occurrenceCount,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return existing.id!;
    }
    return _db.insert('knowledge_graph_entities', entity.toMap());
  }

  /// Upserts a batch of entities. Returns inserted/updated count.
  Future<int> upsertEntities(List<KnowledgeEntity> entities) async {
    int count = 0;
    final batch = _db.batch();
    for (final entity in entities) {
      final existing = await _findEntity(entity.type, entity.externalId);
      if (existing != null) {
        batch.update(
          'knowledge_graph_entities',
          {
            'display_name': entity.displayName ?? existing.displayName,
            'occurrence_count': entity.occurrenceCount,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [existing.id],
        );
        count++;
      } else {
        batch.insert('knowledge_graph_entities', entity.toMap());
        count++;
      }
    }
    await batch.commit(noResult: true);
    return count;
  }

  /// Finds an entity by composite key.
  Future<KnowledgeEntity?> findEntity(
    KnowledgeEntityType type,
    String externalId,
  ) async {
    return _findEntity(type, externalId);
  }

  Future<KnowledgeEntity?> _findEntity(
    KnowledgeEntityType type,
    String externalId,
  ) async {
    final rows = await _db.query(
      'knowledge_graph_entities',
      where: 'type = ? AND external_id = ?',
      whereArgs: [type.value, externalId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return KnowledgeEntity.fromMap(rows.first);
  }

  /// Returns all entities of a given type.
  Future<List<KnowledgeEntity>> getEntitiesByType(
    KnowledgeEntityType type, {
    int limit = 500,
  }) async {
    final rows = await _db.query(
      'knowledge_graph_entities',
      where: 'type = ?',
      whereArgs: [type.value],
      orderBy: 'occurrence_count DESC',
      limit: limit,
    );
    return rows.map(KnowledgeEntity.fromMap).toList();
  }

  /// Returns entities by a list of external IDs.
  Future<List<KnowledgeEntity>> getEntitiesByExternalIds(
    List<String> externalIds,
  ) async {
    if (externalIds.isEmpty) return [];
    final placeholders = externalIds.map((_) => '?').join(',');
    final rows = await _db.query(
      'knowledge_graph_entities',
      where: 'external_id IN ($placeholders)',
      whereArgs: externalIds,
    );
    return rows.map(KnowledgeEntity.fromMap).toList();
  }

  /// Deletes an entity and all its relationships.
  Future<void> deleteEntity(KnowledgeEntityType type, String externalId) async {
    final entity = await _findEntity(type, externalId);
    if (entity == null || entity.id == null) return;
    await _db.delete(
      'knowledge_graph_relationships',
      where: 'source_entity_id = ? OR target_entity_id = ?',
      whereArgs: [externalId, externalId],
    );
    await _db.delete(
      'knowledge_graph_entities',
      where: 'id = ?',
      whereArgs: [entity.id],
    );
  }

  // ── Relationship operations ────────────────────────────────────────

  /// Upserts a single relationship.
  Future<int> upsertRelationship(KnowledgeRelationship rel) async {
    final existing = await _findRelationship(
      rel.relationType,
      rel.sourceEntityId,
      rel.targetEntityId,
    );
    if (existing != null) {
      // Update confidence (take higher), weight (accumulate), evidence
      final newConfidence =
          rel.confidence > existing.confidence ? rel.confidence : existing.confidence;
      final newWeight = existing.weight + rel.weight;
      await _db.update(
        'knowledge_graph_relationships',
        {
          'confidence': newConfidence,
          'weight': newWeight,
          'evidence_source': rel.evidenceSource.value,
          'evidence_detail': rel.evidenceDetail,
          'analysis_version': rel.analysisVersion,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return existing.id!;
    }
    return _db.insert('knowledge_graph_relationships', rel.toMap());
  }

  /// Upserts a batch of relationships.
  Future<int> upsertRelationships(List<KnowledgeRelationship> rels) async {
    int count = 0;
    for (final rel in rels) {
      await upsertRelationship(rel);
      count++;
    }
    return count;
  }

  Future<KnowledgeRelationship?> _findRelationship(
    KnowledgeRelationType type,
    String sourceId,
    String targetId,
  ) async {
    final rows = await _db.query(
      'knowledge_graph_relationships',
      where:
          'relation_type = ? AND source_entity_id = ? AND target_entity_id = ?',
      whereArgs: [type.value, sourceId, targetId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return KnowledgeRelationship.fromMap(rows.first);
  }

  /// Returns all relationships where the given entity is the source.
  Future<List<KnowledgeRelationship>> getOutgoing(
    String entityId, {
    KnowledgeRelationType? type,
    double minConfidence = 0.0,
  }) async {
    String where = 'source_entity_id = ? AND confidence >= ?';
    List<Object?> args = [entityId, minConfidence];
    if (type != null) {
      where += ' AND relation_type = ?';
      args.add(type.value);
    }
    final rows = await _db.query(
      'knowledge_graph_relationships',
      where: where,
      whereArgs: args,
      orderBy: 'confidence DESC, weight DESC',
    );
    return rows.map(KnowledgeRelationship.fromMap).toList();
  }

  /// Returns all relationships where the given entity is the target.
  Future<List<KnowledgeRelationship>> getIncoming(
    String entityId, {
    KnowledgeRelationType? type,
    double minConfidence = 0.0,
  }) async {
    String where = 'target_entity_id = ? AND confidence >= ?';
    List<Object?> args = [entityId, minConfidence];
    if (type != null) {
      where += ' AND relation_type = ?';
      args.add(type.value);
    }
    final rows = await _db.query(
      'knowledge_graph_relationships',
      where: where,
      whereArgs: args,
      orderBy: 'confidence DESC, weight DESC',
    );
    return rows.map(KnowledgeRelationship.fromMap).toList();
  }

  /// Returns all relationships of a given type.
  Future<List<KnowledgeRelationship>> getRelationshipsByType(
    KnowledgeRelationType type, {
    int limit = 500,
  }) async {
    final rows = await _db.query(
      'knowledge_graph_relationships',
      where: 'relation_type = ?',
      whereArgs: [type.value],
      orderBy: 'confidence DESC, weight DESC',
      limit: limit,
    );
    return rows.map(KnowledgeRelationship.fromMap).toList();
  }

  /// Two-hop traversal: find entities connected to `startEntityId` via
  /// an intermediate entity. Returns (neighborEntity, intermediateEntity, rel1, rel2).
  Future<List<GraphNeighbor>> getTwoHopNeighbors(
    String startEntityId, {
    KnowledgeRelationType? firstHopType,
    KnowledgeRelationType? secondHopType,
    double minConfidence = 0.0,
    int limit = 50,
  }) async {
    String where = '''
      r1.source_entity_id = ? AND r1.confidence >= ?
      AND r2.source_entity_id = r1.target_entity_id AND r2.confidence >= ?
      AND r1.target_entity_id != ?
    ''';
    List<Object?> args = [
      startEntityId,
      minConfidence,
      minConfidence,
      startEntityId,
    ];
    if (firstHopType != null) {
      where += ' AND r1.relation_type = ?';
      args.add(firstHopType.value);
    }
    if (secondHopType != null) {
      where += ' AND r2.relation_type = ?';
      args.add(secondHopType.value);
    }

    final rows = await _db.rawQuery('''
      SELECT
        e2.id AS neighbor_id, e2.type AS neighbor_type,
        e2.external_id AS neighbor_external_id, e2.display_name AS neighbor_display_name,
        e2.occurrence_count AS neighbor_occurrence_count,
        e2.created_at AS neighbor_created_at, e2.updated_at AS neighbor_updated_at,
        r1.relation_type AS r1_type, r1.source_entity_id AS r1_source,
        r1.target_entity_id AS r1_target, r1.confidence AS r1_confidence,
        r1.evidence_source AS r1_evidence_source, r1.weight AS r1_weight,
        r1.created_at AS r1_created_at, r1.updated_at AS r1_updated_at,
        r2.relation_type AS r2_type, r2.source_entity_id AS r2_source,
        r2.target_entity_id AS r2_target, r2.confidence AS r2_confidence,
        r2.evidence_source AS r2_evidence_source, r2.weight AS r2_weight,
        r2.created_at AS r2_created_at, r2.updated_at AS r2_updated_at
      FROM knowledge_graph_relationships r1
      JOIN knowledge_graph_relationships r2 ON r1.target_entity_id = r2.source_entity_id
      JOIN knowledge_graph_entities e2 ON e2.external_id = r2.target_entity_id
      WHERE $where
      LIMIT ?
    ''', [...args, limit]);

    return rows.map((row) {
      final neighbor = KnowledgeEntity(
        id: row['neighbor_id'] as int?,
        type: KnowledgeEntityTypeExtension.fromValue(row['neighbor_type'] as String),
        externalId: row['neighbor_external_id'] as String,
        displayName: row['neighbor_display_name'] as String?,
        occurrenceCount: row['neighbor_occurrence_count'] as int? ?? 1,
        createdAt: DateTime.parse(row['neighbor_created_at'] as String),
        updatedAt: DateTime.parse(row['neighbor_updated_at'] as String),
      );
      final rel1 = KnowledgeRelationship(
        relationType: KnowledgeRelationTypeExtension.fromValue(
          row['r1_type'] as String,
        ),
        sourceEntityId: row['r1_source'] as String,
        targetEntityId: row['r1_target'] as String,
        confidence: (row['r1_confidence'] as num?)?.toDouble() ?? 1.0,
        evidenceSource: EvidenceSourceExtension.fromValue(
          row['r1_evidence_source'] as String,
        ),
        weight: row['r1_weight'] as int? ?? 1,
        createdAt: DateTime.parse(row['r1_created_at'] as String),
        updatedAt: DateTime.parse(row['r1_updated_at'] as String),
      );
      final rel2 = KnowledgeRelationship(
        relationType: KnowledgeRelationTypeExtension.fromValue(
          row['r2_type'] as String,
        ),
        sourceEntityId: row['r2_source'] as String,
        targetEntityId: row['r2_target'] as String,
        confidence: (row['r2_confidence'] as num?)?.toDouble() ?? 1.0,
        evidenceSource: EvidenceSourceExtension.fromValue(
          row['r2_evidence_source'] as String,
        ),
        weight: row['r2_weight'] as int? ?? 1,
        createdAt: DateTime.parse(row['r2_created_at'] as String),
        updatedAt: DateTime.parse(row['r2_updated_at'] as String),
      );
      return GraphNeighbor(
        neighbor: neighbor,
        intermediateEntityId: rel1.targetEntityId,
        firstHop: rel1,
        secondHop: rel2,
      );
    }).toList();
  }

  // ── Aggregate queries ──────────────────────────────────────────────

  /// Returns entity count by type.
  Future<Map<String, int>> getEntityCounts() async {
    final rows = await _db.rawQuery('''
      SELECT type, COUNT(*) as count
      FROM knowledge_graph_entities
      GROUP BY type
    ''');
    return {
      for (final row in rows)
        row['type'] as String: row['count'] as int,
    };
  }

  /// Returns relationship count by type.
  Future<Map<String, int>> getRelationshipCounts() async {
    final rows = await _db.rawQuery('''
      SELECT relation_type, COUNT(*) as count
      FROM knowledge_graph_relationships
      GROUP BY relation_type
    ''');
    return {
      for (final row in rows)
        row['relation_type'] as String: row['count'] as int,
    };
  }

  /// Returns total entity and relationship counts.
  Future<Map<String, int>> getGraphStats() async {
    final entityCount = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM knowledge_graph_entities'),
    );
    final relCount = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM knowledge_graph_relationships'),
    );
    return {
      'total_entities': entityCount ?? 0,
      'total_relationships': relCount ?? 0,
    };
  }

  /// Returns the top N entities by occurrence count for a given type.
  Future<List<KnowledgeEntity>> getTopEntities(
    KnowledgeEntityType type, {
    int limit = 20,
  }) async {
    final rows = await _db.query(
      'knowledge_graph_entities',
      where: 'type = ?',
      whereArgs: [type.value],
      orderBy: 'occurrence_count DESC',
      limit: limit,
    );
    return rows.map(KnowledgeEntity.fromMap).toList();
  }

  /// Removes all relationships originating from deleted photos.
  /// Called during photo deletion to keep the graph consistent.
  Future<void> removeMediaRelationships(String photoId) async {
    await _db.delete(
      'knowledge_graph_relationships',
      where: 'source_entity_id = ? OR target_entity_id = ?',
      whereArgs: [photoId, photoId],
    );
    await _db.delete(
      'knowledge_graph_entities',
      where: "type = 'media' AND external_id = ?",
      whereArgs: [photoId],
    );
  }

  /// Removes stale relationships older than the given date.
  Future<int> pruneStaleRelationships(DateTime olderThan) async {
    return _db.delete(
      'knowledge_graph_relationships',
      where: 'updated_at < ?',
      whereArgs: [olderThan.toIso8601String()],
    );
  }
}

/// A result from a two-hop graph traversal.
class GraphNeighbor {
  final KnowledgeEntity neighbor;
  final String intermediateEntityId;
  final KnowledgeRelationship firstHop;
  final KnowledgeRelationship secondHop;

  const GraphNeighbor({
    required this.neighbor,
    required this.intermediateEntityId,
    required this.firstHop,
    required this.secondHop,
  });

  /// Combined confidence score (product of both hops).
  double get combinedConfidence =>
      firstHop.confidence * secondHop.confidence;

  /// Combined weight.
  int get combinedWeight =>
      firstHop.weight + secondHop.weight;
}
