import 'package:sqflite/sqflite.dart';

import '../../../domain/models/knowledge_entity.dart';
import '../../../domain/models/knowledge_relationship.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';

/// Builds and maintains the personal media knowledge graph by deriving
/// deterministic relationships from existing indexed data.
///
/// Relationship sources (all evidence-based, no fabrication):
/// - faces.person_id → media ↔ person
/// - photo_metadata lat/lng → media ↔ place (grid-hashed)
/// - analysis_state.event_id → media ↔ event
/// - object_tags.label → media ↔ object
/// - photo_events photo_ids/person_ids → event ↔ media, event ↔ person
/// - memories photo_ids/person_ids → memory ↔ media, memory ↔ person
/// - co-occurrence in same event → person ↔ person
/// - event proximity in time → event ↔ event
class KnowledgeGraphService {
  KnowledgeGraphService({
    required AppDatabase db,
    required AppLogger logger,
  })  : _db = db,
        _logger = logger;

  final AppDatabase _db;
  final AppLogger _logger;

  /// Builds the full knowledge graph from existing data.
  /// Safe to call multiple times — uses idempotent upserts.
  /// Returns a summary of entities and relationships created.
  Future<KnowledgeGraphStats> buildGraph() async {
    _logger.info('KnowledgeGraphService: starting full graph build');
    final sw = Stopwatch()..start();

    int mediaCount = 0;
    int personCount = 0;
    int placeCount = 0;
    int eventCount = 0;
    int objectCount = 0;
    int memoryCount = 0;
    int relCount = 0;

    // Phase 1: Build entity nodes
    mediaCount = await _buildMediaEntities();
    personCount = await _buildPersonEntities();
    placeCount = await _buildPlaceEntities();
    eventCount = await _buildEventEntities();
    objectCount = await _buildObjectEntities();
    memoryCount = await _buildMemoryEntities();

    // Phase 2: Build relationships
    relCount += await _buildMediaPersonRelationships();
    relCount += await _buildMediaPlaceRelationships();
    relCount += await _buildMediaEventRelationships();
    relCount += await _buildMediaObjectRelationships();
    relCount += await _buildEventPlaceRelationships();
    relCount += await _buildEventPersonRelationships();
    relCount += await _buildMemoryMediaRelationships();
    relCount += await _buildMemoryPersonRelationships();
    relCount += await _buildPersonCoOccurrences();
    relCount += await _buildEventTemporalRelationships();
    relCount += await _buildVideoSegmentRelationships();

    sw.stop();
    final stats = KnowledgeGraphStats(
      mediaEntities: mediaCount,
      personEntities: personCount,
      placeEntities: placeCount,
      eventEntities: eventCount,
      objectEntities: objectCount,
      memoryEntities: memoryCount,
      totalRelationships: relCount,
      buildTimeMs: sw.elapsedMilliseconds,
    );
    _logger.info(
      'KnowledgeGraphService: graph build complete in ${sw.elapsedMilliseconds}ms — '
      '${stats.totalEntities} entities, ${relCount} relationships',
    );
    return stats;
  }

  // ── Entity builders ──────────────────────────────────────────────

  Future<int> _buildMediaEntities() async {
    final rows = await _db.database.rawQuery('''
      SELECT photo_id, date_created, media_type, album_id, folder_path
      FROM photo_metadata
      ORDER BY date_created ASC
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final photoId = row['photo_id'] as String;
      final dateCreated = row['date_created'] as String?;
      final mediaType = row['media_type'] as String? ?? 'photo';
      final displayName = dateCreated != null
          ? '$mediaType ${DateTime.parse(dateCreated).toLocal().toString().substring(0, 16)}'
          : photoId;
      final entity = KnowledgeEntity(
        type: KnowledgeEntityType.media,
        externalId: photoId,
        displayName: displayName,
        createdAt: now,
        updatedAt: now,
      );
      batch.insert(
        'knowledge_graph_entities',
        entity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count++;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count media entities');
    return count;
  }

  Future<int> _buildPersonEntities() async {
    // Batch-fetch face counts per person to avoid N+1 queries
    final faceCountRows = await _db.database.rawQuery('''
      SELECT person_id, COUNT(*) as c
      FROM faces
      WHERE person_id IS NOT NULL
      GROUP BY person_id
    ''');
    final faceCountMap = <String, int>{
      for (final row in faceCountRows)
        row['person_id'] as String: row['c'] as int,
    };

    final rows = await _db.database.rawQuery('''
      SELECT person_id, display_name
      FROM people
      WHERE status = 'active'
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final personId = row['person_id'] as String;
      final displayName = row['display_name'] as String?;
      final faceCount = faceCountMap[personId] ?? 1;
      final entity = KnowledgeEntity(
        type: KnowledgeEntityType.person,
        externalId: personId,
        displayName: displayName,
        occurrenceCount: faceCount,
        createdAt: now,
        updatedAt: now,
      );
      batch.insert(
        'knowledge_graph_entities',
        entity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count++;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count person entities');
    return count;
  }

  Future<int> _buildPlaceEntities() async {
    // Batch-fetch photo counts per grid cell to avoid N+1 queries
    final photoCountRows = await _db.database.rawQuery('''
      SELECT ROUND(latitude, 2) as lat_round, ROUND(longitude, 2) as lng_round, COUNT(*) as c
      FROM photo_metadata
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL
      GROUP BY lat_round, lng_round
    ''');
    final placeCountMap = <String, int>{};
    for (final row in photoCountRows) {
      final lat = (row['lat_round'] as num).toDouble();
      final lng = (row['lng_round'] as num).toDouble();
      placeCountMap[_placeKey(lat, lng)] = row['c'] as int;
    }

    // Use the same grouped query for entities
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in photoCountRows) {
      final lat = (row['lat_round'] as num).toDouble();
      final lng = (row['lng_round'] as num).toDouble();
      final placeKey = _placeKey(lat, lng);
      final photoCount = placeCountMap[placeKey] ?? 1;
      final entity = KnowledgeEntity(
        type: KnowledgeEntityType.place,
        externalId: placeKey,
        displayName: '${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)}',
        occurrenceCount: photoCount,
        createdAt: now,
        updatedAt: now,
      );
      batch.insert(
        'knowledge_graph_entities',
        entity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count++;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count place entities');
    return count;
  }

  Future<int> _buildEventEntities() async {
    final rows = await _db.database.rawQuery('''
      SELECT event_id, title, start_time, confidence
      FROM photo_events
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final eventId = row['event_id'] as String;
      final title = row['title'] as String;
      final entity = KnowledgeEntity(
        type: KnowledgeEntityType.event,
        externalId: eventId,
        displayName: title,
        createdAt: now,
        updatedAt: now,
      );
      batch.insert(
        'knowledge_graph_entities',
        entity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count++;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count event entities');
    return count;
  }

  Future<int> _buildObjectEntities() async {
    final rows = await _db.database.rawQuery('''
      SELECT label, COUNT(*) as c
      FROM object_tags
      GROUP BY label
      ORDER BY c DESC
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final label = row['label'] as String;
      final occurrenceCount = row['c'] as int;
      final entity = KnowledgeEntity(
        type: KnowledgeEntityType.object,
        externalId: label,
        displayName: label,
        occurrenceCount: occurrenceCount,
        createdAt: now,
        updatedAt: now,
      );
      batch.insert(
        'knowledge_graph_entities',
        entity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count++;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count object entities');
    return count;
  }

  Future<int> _buildMemoryEntities() async {
    final rows = await _db.database.rawQuery('''
      SELECT memory_id, title
      FROM memories
      WHERE status = 0
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final memoryId = row['memory_id'] as String;
      final title = row['title'] as String;
      final entity = KnowledgeEntity(
        type: KnowledgeEntityType.memory,
        externalId: memoryId,
        displayName: title,
        createdAt: now,
        updatedAt: now,
      );
      batch.insert(
        'knowledge_graph_entities',
        entity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count++;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count memory entities');
    return count;
  }

  // ── Relationship builders ────────────────────────────────────────

  Future<int> _buildMediaPersonRelationships() async {
    // Media ↔ Person via face detections with person_id
    final rows = await _db.database.rawQuery('''
      SELECT DISTINCT f.photo_id, f.person_id
      FROM faces f
      WHERE f.person_id IS NOT NULL
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final photoId = row['photo_id'] as String;
      final personId = row['person_id'] as String;
      // Forward: media → person
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.mediaIncludesPerson,
          sourceEntityId: photoId,
          targetEntityId: personId,
          confidence: 0.9,
          evidenceSource: EvidenceSource.faceDetection,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      // Reverse: person → media
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.personAppearsInMedia,
          sourceEntityId: personId,
          targetEntityId: photoId,
          confidence: 0.9,
          evidenceSource: EvidenceSource.faceDetection,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count += 2;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count media↔person relationships');
    return count;
  }

  Future<int> _buildMediaPlaceRelationships() async {
    // Media ↔ Place via photo_metadata GPS coordinates
    final rows = await _db.database.rawQuery('''
      SELECT photo_id, latitude, longitude
      FROM photo_metadata
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final photoId = row['photo_id'] as String;
      final lat = (row['latitude'] as num).toDouble();
      final lng = (row['longitude'] as num).toDouble();
      final placeId = _placeKey(lat, lng);
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.mediaAtPlace,
          sourceEntityId: photoId,
          targetEntityId: placeId,
          confidence: 1.0,
          evidenceSource: EvidenceSource.metadataExtraction,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.placeContainsMedia,
          sourceEntityId: placeId,
          targetEntityId: photoId,
          confidence: 1.0,
          evidenceSource: EvidenceSource.metadataExtraction,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count += 2;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count media↔place relationships');
    return count;
  }

  Future<int> _buildMediaEventRelationships() async {
    // Media ↔ Event via analysis_state.event_id
    final rows = await _db.database.rawQuery('''
      SELECT photo_id, event_id
      FROM analysis_state
      WHERE event_id IS NOT NULL
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final photoId = row['photo_id'] as String;
      final eventId = row['event_id'] as String;
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.mediaBelongsToEvent,
          sourceEntityId: photoId,
          targetEntityId: eventId,
          confidence: 0.95,
          evidenceSource: EvidenceSource.eventClustering,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.eventContainsMedia,
          sourceEntityId: eventId,
          targetEntityId: photoId,
          confidence: 0.95,
          evidenceSource: EvidenceSource.eventClustering,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count += 2;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count media↔event relationships');
    return count;
  }

  Future<int> _buildMediaObjectRelationships() async {
    // Media ↔ Object via object_tags
    final rows = await _db.database.rawQuery('''
      SELECT photo_id, label, confidence
      FROM object_tags
      WHERE confidence >= 0.5
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final photoId = row['photo_id'] as String;
      final label = row['label'] as String;
      final confidence = (row['confidence'] as num).toDouble();
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.mediaShowsObject,
          sourceEntityId: photoId,
          targetEntityId: label,
          confidence: confidence,
          evidenceSource: EvidenceSource.objectDetection,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.objectAppearsInMedia,
          sourceEntityId: label,
          targetEntityId: photoId,
          confidence: confidence,
          evidenceSource: EvidenceSource.objectDetection,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count += 2;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count media↔object relationships');
    return count;
  }

  Future<int> _buildEventPlaceRelationships() async {
    // Event ↔ Place via photo_events GPS coordinates
    final rows = await _db.database.rawQuery('''
      SELECT event_id, latitude, longitude
      FROM photo_events
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final eventId = row['event_id'] as String;
      final lat = (row['latitude'] as num).toDouble();
      final lng = (row['longitude'] as num).toDouble();
      final placeId = _placeKey(lat, lng);
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.eventAtPlace,
          sourceEntityId: eventId,
          targetEntityId: placeId,
          confidence: 0.95,
          evidenceSource: EvidenceSource.eventClustering,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.placeHostedEvent,
          sourceEntityId: placeId,
          targetEntityId: eventId,
          confidence: 0.95,
          evidenceSource: EvidenceSource.eventClustering,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count += 2;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count event↔place relationships');
    return count;
  }

  Future<int> _buildEventPersonRelationships() async {
    // Event ↔ Person via faces that belong to photos in that event.
    // This fills the gap where photo_events.person_ids is empty.
    final rows = await _db.database.rawQuery('''
      SELECT DISTINCT a.event_id, f.person_id
      FROM analysis_state a
      JOIN faces f ON f.photo_id = a.photo_id
      WHERE a.event_id IS NOT NULL AND f.person_id IS NOT NULL
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final eventId = row['event_id'] as String;
      final personId = row['person_id'] as String;
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.personAttendedEvent,
          sourceEntityId: personId,
          targetEntityId: eventId,
          confidence: 0.9,
          evidenceSource: EvidenceSource.faceDetection,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.eventAttendedByPerson,
          sourceEntityId: eventId,
          targetEntityId: personId,
          confidence: 0.9,
          evidenceSource: EvidenceSource.faceDetection,
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count += 2;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count event↔person relationships');
    return count;
  }

  Future<int> _buildMemoryMediaRelationships() async {
    // Memory ↔ Media via memories.photo_ids
    final rows = await _db.database.rawQuery('''
      SELECT memory_id, photo_ids
      FROM memories
      WHERE status = 0
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final memoryId = row['memory_id'] as String;
      final photoIdsStr = row['photo_ids'] as String;
      final photoIds = photoIdsStr
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList();
      for (final photoId in photoIds) {
        batch.insert(
          'knowledge_graph_relationships',
          KnowledgeRelationship(
            relationType: KnowledgeRelationType.memoryContainsMedia,
            sourceEntityId: memoryId,
            targetEntityId: photoId,
            confidence: 1.0,
            evidenceSource: EvidenceSource.memoryGeneration,
            analysisVersion: '1.0',
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        batch.insert(
          'knowledge_graph_relationships',
          KnowledgeRelationship(
            relationType: KnowledgeRelationType.mediaBelongsToMemory,
            sourceEntityId: photoId,
            targetEntityId: memoryId,
            confidence: 1.0,
            evidenceSource: EvidenceSource.memoryGeneration,
            analysisVersion: '1.0',
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        count += 2;
      }
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count memory↔media relationships');
    return count;
  }

  Future<int> _buildMemoryPersonRelationships() async {
    // Memory ↔ Person via memories.person_ids
    final rows = await _db.database.rawQuery('''
      SELECT memory_id, person_ids
      FROM memories
      WHERE status = 0 AND person_ids IS NOT NULL AND person_ids != ''
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final memoryId = row['memory_id'] as String;
      final personIdsStr = row['person_ids'] as String;
      final personIds = personIdsStr
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList();
      for (final personId in personIds) {
        batch.insert(
          'knowledge_graph_relationships',
          KnowledgeRelationship(
            relationType: KnowledgeRelationType.memoryContainsPerson,
            sourceEntityId: memoryId,
            targetEntityId: personId,
            confidence: 1.0,
            evidenceSource: EvidenceSource.memoryGeneration,
            analysisVersion: '1.0',
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        batch.insert(
          'knowledge_graph_relationships',
          KnowledgeRelationship(
            relationType: KnowledgeRelationType.personInMemory,
            sourceEntityId: personId,
            targetEntityId: memoryId,
            confidence: 1.0,
            evidenceSource: EvidenceSource.memoryGeneration,
            analysisVersion: '1.0',
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        count += 2;
      }
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count memory↔person relationships');
    return count;
  }

  Future<int> _buildPersonCoOccurrences() async {
    // Person ↔ Person: two people appear in the same event.
    // This is a key graph relationship for "who appears with whom" queries.
    final rows = await _db.database.rawQuery('''
      SELECT DISTINCT a.event_id, f1.person_id AS p1, f2.person_id AS p2
      FROM analysis_state a
      JOIN faces f1 ON f1.photo_id = a.photo_id
      JOIN faces f2 ON f2.photo_id = a.photo_id
      WHERE a.event_id IS NOT NULL
        AND f1.person_id IS NOT NULL
        AND f2.person_id IS NOT NULL
        AND f1.person_id < f2.person_id
    ''');
    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();
    for (final row in rows) {
      final p1 = row['p1'] as String;
      final p2 = row['p2'] as String;
      final eventId = row['event_id'] as String;
      // Bidirectional: p1 ↔ p2
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.peopleCoOccurs,
          sourceEntityId: p1,
          targetEntityId: p2,
          confidence: 0.85,
          evidenceSource: EvidenceSource.eventClustering,
          evidenceDetail: 'event:$eventId',
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.insert(
        'knowledge_graph_relationships',
        KnowledgeRelationship(
          relationType: KnowledgeRelationType.peopleCoOccurs,
          sourceEntityId: p2,
          targetEntityId: p1,
          confidence: 0.85,
          evidenceSource: EvidenceSource.eventClustering,
          evidenceDetail: 'event:$eventId',
          analysisVersion: '1.0',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count += 2;
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count person↔person co-occurrence relationships');
    return count;
  }

  Future<int> _buildEventTemporalRelationships() async {
    // Event ↔ Event: events within 24 hours of each other are temporally related.
    final events = await _db.events.getAll();
    if (events.length < 2) return 0;

    final now = DateTime.now();
    int count = 0;
    final batch = _db.database.batch();

    for (int i = 0; i < events.length; i++) {
      for (int j = i + 1; j < events.length; j++) {
        final a = events[i];
        final b = events[j];
        // Skip if more than 24h apart
        final diff = a.startTime.difference(b.startTime).abs();
        if (diff.inHours > 24) break; // sorted by start_time DESC, so further events are older
        final confidence = (1.0 - diff.inMinutes / 1440.0).clamp(0.3, 1.0);
        batch.insert(
          'knowledge_graph_relationships',
          KnowledgeRelationship(
            relationType: KnowledgeRelationType.eventsTemporal,
            sourceEntityId: a.eventId,
            targetEntityId: b.eventId,
            confidence: confidence,
            evidenceSource: EvidenceSource.inference,
            evidenceDetail: 'time_gap_minutes:${diff.inMinutes}',
            analysisVersion: '1.0',
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        batch.insert(
          'knowledge_graph_relationships',
          KnowledgeRelationship(
            relationType: KnowledgeRelationType.eventsTemporal,
            sourceEntityId: b.eventId,
            targetEntityId: a.eventId,
            confidence: confidence,
            evidenceSource: EvidenceSource.inference,
            evidenceDetail: 'time_gap_minutes:${diff.inMinutes}',
            analysisVersion: '1.0',
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        count += 2;
      }
    }
    await batch.commit(noResult: true);
    _logger.info('KnowledgeGraphService: built $count event↔event temporal relationships');
    return count;
  }

  // ── Video Segment Relationships ─────────────────────────────────

  /// Build relationships from video segments to people and objects.
  ///
  /// Queries `video_segments` for people and labels detected in video
  /// content, then creates media↔person and media↔object relationships
  /// using the video_id as the media entity's external ID.
  Future<int> _buildVideoSegmentRelationships() async {
    try {
    final rows = await _db.database.rawQuery('''
      SELECT video_id, people, labels
      FROM video_segments
      WHERE (people IS NOT NULL AND people != '')
         OR (labels IS NOT NULL AND labels != '')
    ''');

    if (rows.isEmpty) {
      _logger.info('KnowledgeGraphService: no video segment data for relationships');
      return 0;
    }

    final relationships = <KnowledgeRelationship>[];
    final now = DateTime.now();

    // Group by video_id to avoid duplicate relationships
    final videoPeople = <String, Set<String>>{};
    final videoObjects = <String, Set<String>>{};
    for (final row in rows) {
      final videoId = row['video_id'] as String;
      final peopleStr = row['people'] as String? ?? '';
      final labelsStr = row['labels'] as String? ?? '';

      if (peopleStr.isNotEmpty) {
        videoPeople.putIfAbsent(videoId, () => {}).addAll(
          peopleStr.split(',').where((s) => s.isNotEmpty && !s.startsWith('face:')),
        );
      }
      if (labelsStr.isNotEmpty) {
        videoObjects.putIfAbsent(videoId, () => {}).addAll(
          labelsStr.split(',').where((s) => s.isNotEmpty),
        );
      }
    }

    // Media ↔ Person relationships from video segments
    for (final entry in videoPeople.entries) {
      final videoId = entry.key;
      for (final personId in entry.value) {
        relationships.add(KnowledgeRelationship(
          relationType: KnowledgeRelationType.mediaIncludesPerson,
          sourceEntityId: videoId,
          targetEntityId: personId,
          confidence: 0.85,
          evidenceSource: EvidenceSource.faceDetection,
          evidenceDetail: 'video_segment_detection',
          createdAt: now,
          updatedAt: now,
        ));
        relationships.add(KnowledgeRelationship(
          relationType: KnowledgeRelationType.personAppearsInMedia,
          sourceEntityId: personId,
          targetEntityId: videoId,
          confidence: 0.85,
          evidenceSource: EvidenceSource.faceDetection,
          evidenceDetail: 'video_segment_detection',
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    // Media ↔ Object relationships from video segments
    for (final entry in videoObjects.entries) {
      final videoId = entry.key;
      for (final label in entry.value) {
        relationships.add(KnowledgeRelationship(
          relationType: KnowledgeRelationType.mediaShowsObject,
          sourceEntityId: videoId,
          targetEntityId: label,
          confidence: 0.8,
          evidenceSource: EvidenceSource.objectDetection,
          evidenceDetail: 'video_segment_detection',
          createdAt: now,
          updatedAt: now,
        ));
        relationships.add(KnowledgeRelationship(
          relationType: KnowledgeRelationType.objectAppearsInMedia,
          sourceEntityId: label,
          targetEntityId: videoId,
          confidence: 0.8,
          evidenceSource: EvidenceSource.objectDetection,
          evidenceDetail: 'video_segment_detection',
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    if (relationships.isNotEmpty) {
      await _db.knowledgeGraph.upsertRelationships(relationships);
    }

    final count = relationships.length ~/ 2; // count pairs
    _logger.info(
      'KnowledgeGraphService: built $count video segment↔entity relationships',
    );
    return count;
    } catch (e, st) {
      _logger.error('KnowledgeGraphService: video segment relationships failed',
          error: e, stackTrace: st);
      return 0;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Generates a place key from rounded lat/lng (~100m grid cell).
  static String _placeKey(double lat, double lng) {
    return 'place_${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';
  }
}

/// Summary statistics from a graph build operation.
class KnowledgeGraphStats {
  final int mediaEntities;
  final int personEntities;
  final int placeEntities;
  final int eventEntities;
  final int objectEntities;
  final int memoryEntities;
  final int totalRelationships;
  final int buildTimeMs;

  const KnowledgeGraphStats({
    required this.mediaEntities,
    required this.personEntities,
    required this.placeEntities,
    required this.eventEntities,
    required this.objectEntities,
    required this.memoryEntities,
    required this.totalRelationships,
    required this.buildTimeMs,
  });

  int get totalEntities =>
      mediaEntities +
      personEntities +
      placeEntities +
      eventEntities +
      objectEntities +
      memoryEntities;

  @override
  String toString() =>
      'KnowledgeGraphStats(entities: $totalEntities, rels: $totalRelationships, '
      'time: ${buildTimeMs}ms)';
}
