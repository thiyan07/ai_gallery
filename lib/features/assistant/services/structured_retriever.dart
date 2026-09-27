import '../models/gallery_query.dart';
import '../../../core/database/app_database.dart';
import '../../../domain/models/knowledge_entity.dart';
import '../../../domain/models/knowledge_relationship.dart';

/// Executes structured gallery queries against the database.
///
/// Uses direct SQL for counts and statistics (avoids loading all photos).
/// Delegates to SearchService for semantic/embedding-based queries.
class StructuredRetriever {
  StructuredRetriever({required AppDatabase database})
      : _database = database;

  final AppDatabase _database;

  /// Count photos matching a query.
  Future<int> countPhotos(GalleryQuery query) async {
    final where = _buildWhereClause(query);
    final args = _buildWhereArgs(query);

    final result = await _database.database.rawQuery(
      'SELECT COUNT(*) as c FROM photos p '
      'LEFT JOIN photo_metadata pm ON p.id = pm.photo_id '
      'LEFT JOIN analysis_state a ON p.id = a.photo_id '
      '$where',
      args,
    );

    return result.first['c'] as int? ?? 0;
  }

  /// Get total photo count.
  Future<int> getTotalPhotoCount() async {
    final result = await _database.database.rawQuery(
        "SELECT COUNT(*) as c FROM photo_metadata WHERE media_type != 'video'");
    return result.first['c'] as int? ?? 0;
  }

  /// Get total media count (photos + videos).
  Future<int> getTotalMediaCount() async {
    final result = await _database.database.rawQuery(
        'SELECT COUNT(*) as c FROM photo_metadata');
    return result.first['c'] as int? ?? 0;
  }

  /// Get total video count.
  Future<int> getTotalVideoCount() async {
    final result = await _database.database.rawQuery(
        "SELECT COUNT(*) as c FROM photo_metadata WHERE media_type = 'video'");
    return result.first['c'] as int? ?? 0;
  }

  /// Get total video duration in seconds.
  Future<int> getTotalVideoDurationSeconds() async {
    final result = await _database.database.rawQuery(
        "SELECT COALESCE(SUM(duration_seconds), 0) as total FROM photo_metadata WHERE media_type = 'video'");
    return result.first['total'] as int? ?? 0;
  }

  /// Get photos by month for a given year.
  Future<List<MapEntry<String, int>>> getPhotosByMonth({int? year}) async {
    final whereClause = year != null ? 'WHERE strftime("%Y", date_created) = ?' : '';
    final args = year != null ? [year.toString()] : <Object>[];

    final rows = await _database.database.rawQuery(
      'SELECT strftime("%m", date_created) as month, COUNT(*) as c '
      'FROM photo_metadata $whereClause '
      'GROUP BY month ORDER BY month',
      args,
    );

    return rows.map((r) {
      final m = int.parse(r['month'] as String);
      final names = [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return MapEntry(names[m], r['c'] as int);
    }).toList();
  }

  /// Get photos by year.
  Future<List<MapEntry<String, int>>> getPhotosByYear() async {
    final rows = await _database.database.rawQuery(
      'SELECT strftime("%Y", date_created) as year, COUNT(*) as c '
      'FROM photo_metadata '
      'GROUP BY year ORDER BY year',
    );

    return rows
        .map((r) => MapEntry(r['year'] as String, r['c'] as int))
        .toList();
  }

  /// Get top object labels with counts.
  Future<List<MapEntry<String, int>>> getTopObjects({int limit = 10}) async {
    final rows = await _database.database.rawQuery(
      'SELECT label, COUNT(*) as c FROM object_tags '
      'GROUP BY label ORDER BY c DESC LIMIT ?',
      [limit],
    );

    return rows
        .map((r) => MapEntry(r['label'] as String, r['c'] as int))
        .toList();
  }

  /// Get face/person statistics.
  Future<Map<String, dynamic>> getPersonStats() async {
    final personCount = await _database.database
        .rawQuery("SELECT COUNT(*) as c FROM people WHERE status = 'active'");
    final faceCount = await _database.database
        .rawQuery('SELECT COUNT(*) as c FROM faces');

    return {
      'personCount': personCount.first['c'] as int? ?? 0,
      'faceCount': faceCount.first['c'] as int? ?? 0,
    };
  }

  /// Get blurry photo count.
  Future<int> getBlurryPhotoCount() async {
    final result = await _database.database.rawQuery(
      "SELECT COUNT(*) as c FROM photo_metadata WHERE blur_score > 0.6",
    );
    return result.first['c'] as int? ?? 0;
  }

  /// Get screenshot count.
  Future<int> getScreenshotCount() async {
    final result = await _database.database.rawQuery(
      'SELECT COUNT(*) as c FROM analysis_state WHERE is_screenshot = 1',
    );
    return result.first['c'] as int? ?? 0;
  }

  /// Get duplicate group count.
  Future<int> getDuplicateGroupCount() async {
    return _database.duplicates.count();
  }

  /// Get event count.
  Future<int> getEventCount() async {
    return _database.events.count();
  }

  /// Get memory count.
  Future<int> getMemoryCount() async {
    return _database.memories.getActiveMemoryCount();
  }

  /// Get favorite count.
  Future<int> getFavoriteCount() async {
    final result =
        await _database.database.rawQuery('SELECT COUNT(*) as c FROM favorites');
    return result.first['c'] as int? ?? 0;
  }

  /// Get photos with GPS location.
  Future<int> getPhotosWithLocationCount() async {
    final result = await _database.database.rawQuery(
      'SELECT COUNT(*) as c FROM photo_metadata '
      'WHERE latitude IS NOT NULL AND longitude IS NOT NULL',
    );
    return result.first['c'] as int? ?? 0;
  }

  /// Get gallery overview statistics.
  Future<Map<String, dynamic>> getGalleryStats() async {
    final total = await getTotalPhotoCount();
    final videos = await getTotalVideoCount();
    final favorites = await getFavoriteCount();
    final withLocation = await getPhotosWithLocationCount();
    final blurry = await getBlurryPhotoCount();
    final screenshots = await getScreenshotCount();
    final duplicates = await getDuplicateGroupCount();
    final events = await getEventCount();
    final memories = await getMemoryCount();
    final personStats = await getPersonStats();
    final topObjects = await getTopObjects(limit: 5);

    return {
      'totalPhotos': total,
      'totalVideos': videos,
      'favorites': favorites,
      'withLocation': withLocation,
      'blurry': blurry,
      'screenshots': screenshots,
      'duplicateGroups': duplicates,
      'events': events,
      'memories': memories,
      'people': personStats['personCount'],
      'faces': personStats['faceCount'],
      'topObjects': topObjects.map((e) => {'label': e.key, 'count': e.value}).toList(),
    };
  }

  /// Get photo IDs matching a structured query (for non-semantic queries).
  Future<List<String>> getPhotoIds(GalleryQuery query, {int limit = 20}) async {
    final where = _buildWhereClause(query);
    final args = _buildWhereArgs(query);

    final rows = await _database.database.rawQuery(
      'SELECT p.id FROM photos p '
      'LEFT JOIN photo_metadata pm ON p.id = pm.photo_id '
      'LEFT JOIN analysis_state a ON p.id = a.photo_id '
      'LEFT JOIN favorites f ON p.id = f.asset_id '
      '$where '
      'ORDER BY pm.date_created DESC '
      'LIMIT ?',
      [...args, limit],
    );

    return rows.map((r) => r['id'] as String).toList();
  }

  /// Get person's photo IDs.
  Future<List<String>> getPersonPhotoIds(
    String personId, {
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 50,
  }) async {
    var where = 'WHERE f.person_id = ?';
    final args = <Object>[personId];

    if (dateFrom != null) {
      where += ' AND pm.date_created >= ?';
      args.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      where += ' AND pm.date_created <= ?';
      args.add(dateTo.toIso8601String());
    }

    final rows = await _database.database.rawQuery(
      'SELECT DISTINCT p.id FROM photos p '
      'JOIN faces f ON p.id = f.photo_id '
      'LEFT JOIN photo_metadata pm ON p.id = pm.photo_id '
      '$where '
      'ORDER BY pm.date_created DESC '
      'LIMIT ?',
      [...args, limit],
    );

    return rows.map((r) => r['id'] as String).toList();
  }

  /// Get event photo IDs.
  Future<List<String>> getEventPhotoIds(String eventId) async {
    final event = await _database.events.getById(eventId);
    return event?.photoIds ?? [];
  }

  /// Build WHERE clause from GalleryQuery.
  String _buildWhereClause(GalleryQuery query) {
    final conditions = <String>[];

    if (query.hasDateFilter) {
      if (query.dateFrom != null) {
        conditions.add('pm.date_created >= ?');
      }
      if (query.dateTo != null) {
        conditions.add('pm.date_created <= ?');
      }
    }

    if (query.hasObjectFilter) {
      // Use parameterized EXISTS subquery for object tags (no string interpolation)
      for (final label in query.objectLabels) {
        conditions.add(
          'EXISTS (SELECT 1 FROM object_tags ot WHERE ot.photo_id = p.id '
          'AND ot.label = ?)',
        );
      }
    }

    if (query.hasLocationFilter) {
      conditions.add('pm.latitude IS NOT NULL');
    }

    if (query.minQuality != null) {
      conditions.add('pm.quality_score >= ?');
    }

    if (query.maxBlur != null) {
      conditions.add('pm.blur_score <= ?');
    }

    if (query.isScreenshot == true) {
      conditions.add('a.is_screenshot = 1');
    } else if (query.isScreenshot == false) {
      conditions.add('(a.is_screenshot = 0 OR a.is_screenshot IS NULL)');
    }

    if (query.isDocument == true) {
      conditions.add('a.is_document = 1');
    }

    if (query.favoritesOnly == true) {
      conditions.add('f.asset_id IS NOT NULL');
    }

    if (conditions.isEmpty) return '';
    return 'WHERE ${conditions.join(' AND ')}';
  }

  /// Build WHERE args from GalleryQuery.
  List<Object> _buildWhereArgs(GalleryQuery query) {
    final args = <Object>[];

    if (query.dateFrom != null) {
      args.add(query.dateFrom!.toIso8601String());
    }
    if (query.dateTo != null) {
      args.add(query.dateTo!.toIso8601String());
    }
    // Object labels must be bound in the same positional order they appear in
    // _buildWhereClause (dateFrom, dateTo, objects, minQuality, maxBlur).
    if (query.hasObjectFilter) {
      for (final label in query.objectLabels) {
        args.add(label);
      }
    }
    if (query.minQuality != null) {
      args.add(query.minQuality!);
    }
    if (query.maxBlur != null) {
      args.add(query.maxBlur!);
    }

    return args;
  }

  // ── Knowledge Graph queries ────────────────────────────────────

  /// Get people who co-occur with a given person (appear in the same events).
  Future<List<Map<String, dynamic>>> getPersonCoOccurrences(
    String personId, {
    int limit = 10,
  }) async {
    final neighbors = await _database.knowledgeGraph.getTwoHopNeighbors(
      personId,
      firstHopType: KnowledgeRelationType.peopleCoOccurs,
      limit: limit,
    );

    // Aggregate by neighbor, counting co-occurrences
    final Map<String, Map<String, dynamic>> aggregated = {};
    for (final n in neighbors) {
      final key = n.neighbor.externalId;
      if (aggregated.containsKey(key)) {
        aggregated[key]!['count'] =
            (aggregated[key]!['count'] as int) + n.combinedWeight;
        aggregated[key]!['confidence'] = (aggregated[key]!['confidence'] as double) >
                n.combinedConfidence
            ? (aggregated[key]!['confidence'] as double)
            : n.combinedConfidence;
      } else {
        aggregated[key] = {
          'personId': key,
          'displayName': n.neighbor.displayName,
          'count': n.combinedWeight,
          'confidence': n.combinedConfidence,
        };
      }
    }

    final results = aggregated.values.toList();
    results.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return results.take(limit).toList();
  }

  /// Get events a person attended.
  Future<List<Map<String, dynamic>>> getPersonEvents(
    String personId, {
    int limit = 20,
  }) async {
    final relationships = await _database.knowledgeGraph.getOutgoing(
      personId,
      type: KnowledgeRelationType.personAttendedEvent,
    );

    final results = <Map<String, dynamic>>[];
    for (final rel in relationships.take(limit)) {
      final eventEntity = await _database.knowledgeGraph.findEntity(
        KnowledgeEntityType.event,
        rel.targetEntityId,
      );
      if (eventEntity != null) {
        results.add({
          'eventId': rel.targetEntityId,
          'title': eventEntity.displayName,
          'confidence': rel.confidence,
        });
      }
    }
    return results;
  }

  /// Get places a person has visited (via photos with GPS).
  Future<List<Map<String, dynamic>>> getPersonPlaces(
    String personId, {
    int limit = 20,
  }) async {
    // Two-hop: person → media → place
    final neighbors = await _database.knowledgeGraph.getTwoHopNeighbors(
      personId,
      firstHopType: KnowledgeRelationType.personAppearsInMedia,
      secondHopType: KnowledgeRelationType.mediaAtPlace,
      limit: limit * 3,
    );

    final Map<String, Map<String, dynamic>> aggregated = {};
    for (final n in neighbors) {
      final key = n.neighbor.externalId;
      if (aggregated.containsKey(key)) {
        aggregated[key]!['visitCount'] =
            (aggregated[key]!['visitCount'] as int) + 1;
      } else {
        aggregated[key] = {
          'placeId': key,
          'displayName': n.neighbor.displayName,
          'visitCount': 1,
        };
      }
    }

    final results = aggregated.values.toList();
    results.sort(
        (a, b) => (b['visitCount'] as int).compareTo(a['visitCount'] as int));
    return results.take(limit).toList();
  }

  /// Get people who attended a specific event.
  Future<List<Map<String, dynamic>>> getEventPeople(String eventId) async {
    final relationships = await _database.knowledgeGraph.getIncoming(
      eventId,
      type: KnowledgeRelationType.eventAttendedByPerson,
    );

    final results = <Map<String, dynamic>>[];
    for (final rel in relationships) {
      final personEntity = await _database.knowledgeGraph.findEntity(
        KnowledgeEntityType.person,
        rel.sourceEntityId,
      );
      if (personEntity != null) {
        results.add({
          'personId': rel.sourceEntityId,
          'displayName': personEntity.displayName,
          'confidence': rel.confidence,
        });
      }
    }
    return results;
  }

  /// Get all graph connections for a specific photo.
  Future<Map<String, dynamic>> getMediaConnections(String photoId) async {
    final outgoing = await _database.knowledgeGraph.getOutgoing(photoId);
    final incoming = await _database.knowledgeGraph.getIncoming(photoId);

    final connections = <String, List<Map<String, dynamic>>>{};
    for (final rel in outgoing) {
      final type = rel.relationType.value;
      connections[type] ??= [];
      connections[type]!.add({
        'target': rel.targetEntityId,
        'confidence': rel.confidence,
        'source': rel.evidenceSource.value,
      });
    }
    for (final rel in incoming) {
      final type = 'incoming_${rel.relationType.value}';
      connections[type] ??= [];
      connections[type]!.add({
        'source': rel.sourceEntityId,
        'confidence': rel.confidence,
        'evidence': rel.evidenceSource.value,
      });
    }

    return {
      'photoId': photoId,
      'outgoingCount': outgoing.length,
      'incomingCount': incoming.length,
      'connections': connections,
    };
  }

  /// Get knowledge graph statistics.
  Future<Map<String, dynamic>> getGraphStats() async {
    final entityCounts = await _database.knowledgeGraph.getEntityCounts();
    final relCounts = await _database.knowledgeGraph.getRelationshipCounts();
    final overall = await _database.knowledgeGraph.getGraphStats();

    return {
      'totalEntities': overall['total_entities'] ?? 0,
      'totalRelationships': overall['total_relationships'] ?? 0,
      'entityCounts': entityCounts,
      'relationshipCounts': relCounts,
    };
  }
}
