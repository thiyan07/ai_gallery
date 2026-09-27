import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../errors/app_exception.dart' as app_exceptions;
import '../logging/app_logger.dart';
import 'daos/ai_job_dao.dart';
import 'daos/analysis_dao.dart';
import 'daos/correction_dao.dart';
import 'daos/duplicate_dao.dart';
import 'daos/embedding_dao.dart';
import 'daos/event_dao.dart';
import 'daos/face_dao.dart';
import 'daos/favorites_dao.dart';
import 'daos/object_tag_dao.dart';
import 'daos/ocr_dao.dart';
import 'daos/photo_metadata_dao.dart';
import 'daos/people_dao.dart';
import 'daos/memory_dao.dart';
import 'daos/edit_dao.dart';
import 'daos/search_feedback_dao.dart';
import 'daos/trash_dao.dart';
import 'daos/visibility_dao.dart';
import 'daos/smart_album_dao.dart';
import 'daos/video_segment_dao.dart';
import 'daos/video_analysis_dao.dart';
import 'daos/video_frame_dao.dart';
import 'daos/knowledge_graph_dao.dart';

/// Central SQLite database for AI Gallery metadata.
class AppDatabase {
  AppDatabase._(this._db);

  static AppDatabase? _instance;
  static const _dbName = 'ai_gallery.db';
  static const _dbVersion = 19;

  final Database _db;

  /// Getter for the underlying SQLite database for raw queries.
  Database get database => _db;

  late final FavoritesDao favorites = FavoritesDao(_db);
  late final AiJobDao aiJobs = AiJobDao(_db);
  late final PhotoMetadataDao photoMetadata = PhotoMetadataDao(_db);
  late final FaceDao faces = FaceDao(_db);
  late final ObjectTagDao objectTags = ObjectTagDao(_db);
  late final OcrDao ocrResults = OcrDao(_db);
  late final EmbeddingDao embeddings = EmbeddingDao(_db);
  late final SearchFeedbackDao searchFeedback = SearchFeedbackDao(_db);
  late final TrashDao trash = TrashDao(_db);
  late final VisibilityDao visibility = VisibilityDao(_db);
  late final PeopleDao peopleDao = PeopleDao(_db);
  late final MemoryDao memories = MemoryDao(_db);
  late final EditDao editRecipes = EditDao(_db);
  late final AnalysisDao analysisState = AnalysisDao(_db);
  late final DuplicateDao duplicates = DuplicateDao(_db);
  late final EventDao events = EventDao(_db);
  late final SmartAlbumDao smartAlbums = SmartAlbumDao(_db);
  late final CorrectionDao corrections = CorrectionDao(_db);
  late final VideoSegmentDao videoSegments = VideoSegmentDao(_db);
  late final VideoAnalysisDao videoAnalysis = VideoAnalysisDao(_db);
  late final VideoFrameDao videoFrames = VideoFrameDao(_db);
  late final KnowledgeGraphDao knowledgeGraph = KnowledgeGraphDao(_db);

  /// Opens or returns the singleton database instance.
  /// Uses a synchronized Completer to ensure only one concurrent open runs.
  static Future<AppDatabase> open({AppLogger? logger}) async {
    if (_instance != null) return _instance!;
    final existing = _openCompleter;
    if (existing != null) return existing.future;

    final completer = Completer<AppDatabase>();
    _openCompleter = completer;
    try {
      final db = await _openInternal(logger);
      if (!completer.isCompleted) completer.complete(db);
    } catch (e, st) {
      if (!completer.isCompleted) completer.completeError(e, st);
      _openCompleter = null;
      rethrow;
    }
    return completer.future;
  }

  static Completer<AppDatabase>? _openCompleter;

  static Future<AppDatabase> _openInternal(AppLogger? logger) async {
    try {
      final dbPath = await getDatabasesPath();
      final db = await openDatabase(
        join(dbPath, _dbName),
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      // Enable WAL mode for concurrent read/write (critical with background isolate)
      await _enableWalMode(db);
      // Enable foreign key enforcement
      await db.execute('PRAGMA foreign_keys = ON');
      // Set busy timeout to avoid immediate failure on lock contention
      await db.rawQuery('PRAGMA busy_timeout = 5000');
      _instance = AppDatabase._(db);
      logger?.info('AppDatabase opened at ${join(dbPath, _dbName)}');
      return _instance!;
    } catch (e, st) {
      logger?.error('Failed to open AppDatabase', error: e, stackTrace: st);
      throw app_exceptions.DatabaseException(
        'Failed to open database',
        cause: e,
      );
    } finally {
      _openCompleter = null;
    }
  }

  /// Closes the database and clears the singleton (for tests).
  static Future<void> closeForTesting() async {
    await _instance?._db.close();
    _instance = null;
  }

  /// Opens a new database connection for use in a background isolate.
  /// This creates a separate connection that won't conflict with the main isolate's singleton.
  static Future<AppDatabase> openForIsolate({
    required String databasePath,
    AppLogger? logger,
  }) async {
    try {
      final db = await openDatabase(
        databasePath,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      // Enable WAL mode and foreign keys for isolate connection
      await _enableWalMode(db);
      await db.execute('PRAGMA foreign_keys = ON');
      await db.rawQuery('PRAGMA busy_timeout = 5000');
      logger?.info('AppDatabase opened for isolate at $databasePath');
      return AppDatabase._(db);
    } catch (e, st) {
      logger?.error('Failed to open AppDatabase for isolate', error: e, stackTrace: st);
      throw app_exceptions.DatabaseException(
        'Failed to open database for isolate',
        cause: e,
      );
    }
  }

  /// Closes the database connection for this instance (used in isolates).
  Future<void> dispose() async {
    await _db.close();
  }

  static Future<void> _onCreate(Database db, int version) async {
    await _createFavoritesTable(db);
    if (version >= 2) {
      await _createAiMetadataTables(db);
    }
    if (version >= 3) {
      await _createPhotoMetadataTable(db);
      await _createIndexStatusTable(db);
    }
    if (version >= 4) {
      await _createPhotoUsageTable(db);
    }
    if (version >= 6) {
      await _createPeopleTable(db);
      await _addPersonIdToFacesTable(db);
    }
    if (version >= 8) {
      await _createMemoryTables(db);
    }
    if (version >= 9) {
      await _createEditRecipesTable(db);
    }
    if (version >= 10) {
      await _createAnalysisTables(db);
    }
    if (version >= 12) {
      await _createVideoTables(db);
    }
    if (version >= 13) {
      await _createKnowledgeGraphTables(db);
    }
    if (version >= 14) {
      // priority column already present in the fresh ai_jobs table definition
    }
    if (version >= 17) {
      await _createSearchFeedbackTable(db);
    }
    if (version >= 18) {
      await _createTrashTable(db);
    }
    if (version >= 19) {
      await _createVisibilityTable(db);
    }
    // --- Indexes must be created AFTER all tables exist (fresh-create ordering) ---
    if (version >= 7) {
      await _createSearchIndexes(db);
    }
    if (version >= 14) {
      await _createPhase28Indexes(db);
    }
    if (version >= 16) {
      // Fix #5 indexes already in _createSearchIndexes, no extra action for fresh DB
    }
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createAiMetadataTables(db);
    }
    if (oldVersion < 3) {
      await _createPhotoMetadataTable(db);
      await _createIndexStatusTable(db);
    }
    // Repair photo_metadata columns that were only ever added to the CREATE
    // TABLE definition (never via ALTER) for databases created at older schema
    // versions. The search/Phase-28 indexes reference media_type, so open
    // previously threw "no such column: media_type" on such DBs. This must run
    // before the index-creation steps below.
    await _repairPhotoMetadataColumns(db);
    if (oldVersion < 4) {
      await _createPhotoUsageTable(db);
    }
    if (oldVersion < 5) {
      await _addColumnIfMissing(db, 'photo_metadata', 'face_status', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'photo_metadata', 'face_model_version', 'TEXT');
    }
    if (oldVersion < 6) {
      await _createPeopleTable(db);
      await _addPersonIdToFacesTable(db);
      // Migrate existing labels to persons if needed
      await _migrateLabelsToPersons(db);
    }
    if (oldVersion < 7) {
      await _createSearchIndexes(db);
    }
    if (oldVersion < 8) {
      await _createMemoryTables(db);
    }
    if (oldVersion < 9) {
      await _createEditRecipesTable(db);
    }
    if (oldVersion < 10) {
      await _createAnalysisTables(db);
    }
    if (oldVersion < 11) {
      // Add retry_count column for job retry tracking
      await _addColumnIfMissing(db, 'ai_jobs', 'retry_count', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 12) {
      // Phase 25: Add video support columns and tables
      await _addColumnIfMissing(db, 'photo_metadata', 'duration_seconds', 'INTEGER NOT NULL DEFAULT 0');
      await _createVideoTables(db);
    }
    if (oldVersion < 13) {
      // Phase 26: Knowledge graph tables for personal media relationship tracking
      await _createKnowledgeGraphTables(db);
    }
    if (oldVersion < 14) {
      // Phase 28: Add priority column to ai_jobs + missing performance indexes
      await _addColumnIfMissing(db, 'ai_jobs', 'priority', 'INTEGER NOT NULL DEFAULT 1');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_jobs_priority ON ai_jobs(priority DESC, created_at ASC)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_jobs_status_priority ON ai_jobs(status, priority DESC, created_at ASC)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_people_status ON people(status)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_indexed_at ON photo_metadata(indexed_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_date_created_media ON photo_metadata(date_created, media_type)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_photo_id ON analysis_state(photo_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_analyzed_at ON analysis_state(analyzed_at)');
    }
    if (oldVersion < 15) {
      // Phase 31: Re-run index creation that previously failed on older schema
      // DBs missing photo_metadata.media_type (columns are repaired above via
      // _repairPhotoMetadataColumns before any index-creation step runs).
      await _createSearchIndexes(db);
      await _createPhase28Indexes(db);
    }
    if (oldVersion < 16) {
      // Fix #5: Add missing search performance indexes (embeddings.model, ocr_text, etc.)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_embeddings_model ON embeddings(model)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_embeddings_model_photo ON embeddings(model, photo_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_ocr_text_text ON ocr_text(text COLLATE NOCASE)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_object_tags_label_conf ON object_tags(label, confidence DESC)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_faces_person_id_label ON faces(person_id, label)');
    }
    if (oldVersion < 17) {
      // Search upgrades: per-region (object-crop) embeddings for complex scenes
      // + persistent relevance-feedback table ("not relevant" hides).
      await _addColumnIfMissing(db, 'embeddings', 'region_label', 'TEXT');
      await _addColumnIfMissing(db, 'embeddings', 'region_bbox_left', 'REAL');
      await _addColumnIfMissing(db, 'embeddings', 'region_bbox_top', 'REAL');
      await _addColumnIfMissing(db, 'embeddings', 'region_bbox_width', 'REAL');
      await _addColumnIfMissing(db, 'embeddings', 'region_bbox_height', 'REAL');
      await _createSearchFeedbackTable(db);
      await db.execute('CREATE INDEX IF NOT EXISTS idx_embeddings_region ON embeddings(photo_id, region_label)');
    }
    if (oldVersion < 18) {
      // Recycle bin: soft-deleted assets with 30-day retention.
      await _createTrashTable(db);
      // Repair: v17 fresh installs never created search_feedback
      // (_onCreate lacked the v17 block until v18), so ensure it here.
      await _createSearchFeedbackTable(db);
    }
    if (oldVersion < 19) {
      // Archive + Hidden visibility modes (Ente-style organization).
      await _createVisibilityTable(db);
    }
  }

  /// Ensure the photo_metadata table has all columns that were only ever added
  /// to the CREATE TABLE definition (never via ALTER) for databases created at
  /// older schema versions. Without these, index creation referencing them
  /// (e.g. idx_photo_metadata_media_type) fails and the whole DB open throws.
  static Future<void> _repairPhotoMetadataColumns(Database db) async {
    await _addColumnIfMissing(db, 'photo_metadata', 'media_type', 'TEXT');
    await _addColumnIfMissing(db, 'photo_metadata', 'ocr_status', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'photo_metadata', 'ocr_model_version', 'TEXT');
  }

  /// Add a column to a table only if it does not already exist.
  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((r) => r['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  /// Enable WAL mode. Unlike `foreign_keys`/`busy_timeout`, `PRAGMA
  /// journal_mode` returns a result row, so sqflite requires it through
  /// `rawQuery` — calling it via `execute()` throws
  /// "Queries can be performed using SQLiteDatabase query or rawQuery
  /// methods only."
  static Future<void> _enableWalMode(Database db) async {
    await db.rawQuery('PRAGMA journal_mode = WAL');
  }

  static Future<void> _createFavoritesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        asset_id TEXT PRIMARY KEY,
        added_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createAiMetadataTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS faces (
        id TEXT PRIMARY KEY,
        photo_id TEXT NOT NULL,
        bounding_box_left REAL NOT NULL,
        bounding_box_top REAL NOT NULL,
        bounding_box_width REAL NOT NULL,
        bounding_box_height REAL NOT NULL,
        confidence REAL NOT NULL,
        label TEXT,
        embedding BLOB
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS object_tags (
        id TEXT PRIMARY KEY,
        photo_id TEXT NOT NULL,
        label TEXT NOT NULL,
        confidence REAL NOT NULL,
        bounding_box_left REAL,
        bounding_box_top REAL,
        bounding_box_width REAL,
        bounding_box_height REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ocr_text (
        id TEXT PRIMARY KEY,
        photo_id TEXT NOT NULL,
        text TEXT NOT NULL,
        confidence REAL NOT NULL,
        bounding_box_left REAL,
        bounding_box_top REAL,
        bounding_box_width REAL,
        bounding_box_height REAL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS embeddings (
        id TEXT PRIMARY KEY,
        photo_id TEXT NOT NULL,
        model TEXT NOT NULL,
        vector BLOB NOT NULL,
        dimensions INTEGER NOT NULL,
        region_label TEXT,
        region_bbox_left REAL,
        region_bbox_top REAL,
        region_bbox_width REAL,
        region_bbox_height REAL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_jobs (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        photo_id TEXT NOT NULL,
        progress REAL NOT NULL DEFAULT 0,
        error_message TEXT,
        created_at TEXT NOT NULL,
        started_at TEXT,
        completed_at TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  static Future<void> _createPhotoMetadataTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS photo_metadata (
        photo_id TEXT PRIMARY KEY,
        width INTEGER NOT NULL,
        height INTEGER NOT NULL,
        file_size_bytes INTEGER NOT NULL,
        mime_type TEXT,
        date_created TEXT,
        date_modified TEXT,
        camera_make TEXT,
        camera_model TEXT,
        iso INTEGER,
        shutter_speed REAL,
        aperture REAL,
        latitude REAL,
        longitude REAL,
        orientation INTEGER NOT NULL DEFAULT 0,
        dominant_color INTEGER,
        average_color INTEGER,
        brightness REAL,
        contrast REAL,
        blur_score REAL,
        quality_score REAL,
        indexed_at TEXT NOT NULL,
        album_id TEXT,
        folder_path TEXT,
        media_type TEXT,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        ocr_status INTEGER NOT NULL DEFAULT 0,
        ocr_model_version TEXT,
        face_status INTEGER NOT NULL DEFAULT 0,
        face_model_version TEXT
      )
    ''');
  }

  static Future<void> _createPhotoUsageTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS photo_usage (
        photo_id TEXT PRIMARY KEY,
        view_count INTEGER NOT NULL DEFAULT 0,
        last_viewed_at TEXT,
        edited_at TEXT,
        shared_at TEXT,
        FOREIGN KEY (photo_id) REFERENCES photo_metadata(photo_id) ON DELETE CASCADE
      )
    ''');
  }

  /// Search relevance feedback: photos the user marked "not relevant" for a
  /// normalized query. Used to hide them from future runs of that query.
  static Future<void> _createSearchFeedbackTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_feedback (
        photo_id TEXT NOT NULL,
        query TEXT NOT NULL,
        liked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        PRIMARY KEY (photo_id, query)
      )
    ''');
  }

  /// Recycle bin: soft-deleted assets kept for 30 days before permanent
  /// deletion. Trashed assets stay in MediaStore but are hidden from grids.
  static Future<void> _createTrashTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trash (
        asset_id TEXT PRIMARY KEY,
        media_type TEXT,
        deleted_at TEXT NOT NULL
      )
    ''');
  }

  /// Visibility modes: 'archived' (decluttered from timeline, still
  /// searchable) vs 'hidden' (excluded everywhere, PIN-gated to view).
  static Future<void> _createVisibilityTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visibility (
        photo_id TEXT PRIMARY KEY,
        mode TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createIndexStatusTable(Database db) async {    await db.execute('''
      CREATE TABLE IF NOT EXISTS index_status (
        id INTEGER PRIMARY KEY DEFAULT 0,
        last_scanned_at TEXT,
        last_photo_count INTEGER DEFAULT 0
      )
    ''');
    // Insert initial row if it doesn't exist
    await db.insert('index_status', {
      'id': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _createPeopleTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS people (
        person_id TEXT PRIMARY KEY,
        display_name TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        cover_photo_id TEXT,
        status TEXT NOT NULL DEFAULT 'active'
      )
    ''');
  }

  static Future<void> _addPersonIdToFacesTable(Database db) async {
    await _addColumnIfMissing(db, 'faces', 'person_id', 'TEXT');
    // Create index for faster lookups
    await db.execute('CREATE INDEX IF NOT EXISTS idx_faces_person_id ON faces(person_id)');
  }

  static Future<void> _migrateLabelsToPersons(Database db) async {
    // Get all distinct non-null, non-empty labels from faces
    final distinctLabels = await db.rawQuery('''
      SELECT DISTINCT label
      FROM faces
      WHERE label IS NOT NULL AND label != ''
    ''');

    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    for (final row in distinctLabels) {
      final label = row['label'] as String;
      // Stable deterministic ID: sha256(label) truncated to 12 hex chars.
      // Uses crypto (not hashCode which is randomized per isolate).
      final digest = sha256.convert(utf8.encode(label)).toString();
      final personId = 'person_${digest.substring(0, 12)}';

      // Insert person if it doesn't exist
      batch.insert(
        'people',
        {
          'person_id': personId,
          'display_name': label,
          'created_at': now,
          'updated_at': now,
          'status': 'active',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      // Update faces with this label to reference the person
      batch.update(
        'faces',
        {'person_id': personId},
        where: 'label = ? AND person_id IS NULL',
        whereArgs: [label],
      );
    }

    await batch.commit();
  }

  static Future<void> _createSearchIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_faces_photo_id ON faces(photo_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ocr_text_photo_id ON ocr_text(photo_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_embeddings_photo_id ON embeddings(photo_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_date_created ON photo_metadata(date_created)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_object_tags_label ON object_tags(label)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_object_tags_photo_id ON object_tags(photo_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_location ON photo_metadata(latitude, longitude)');
    // Phase 24: Critical missing indexes for job queue performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_jobs_status ON ai_jobs(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_jobs_photo_id ON ai_jobs(photo_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_jobs_status_created ON ai_jobs(status, created_at)');
    // Phase 28: Additional performance indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_jobs_priority ON ai_jobs(priority DESC, created_at ASC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_jobs_status_priority ON ai_jobs(status, priority DESC, created_at ASC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_people_status ON people(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_indexed_at ON photo_metadata(indexed_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_date_created_media ON photo_metadata(date_created, media_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_photo_id ON analysis_state(photo_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_analyzed_at ON analysis_state(analyzed_at)');
    // Fix #5: Missing indexes causing full table scans on search
    await db.execute('CREATE INDEX IF NOT EXISTS idx_embeddings_model ON embeddings(model)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_embeddings_model_photo ON embeddings(model, photo_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ocr_text_text ON ocr_text(text COLLATE NOCASE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_object_tags_label_conf ON object_tags(label, confidence DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_faces_person_id_label ON faces(person_id, label)');
  }

  static Future<void> _createMemoryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        memory_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        subtitle TEXT,
        photo_ids TEXT NOT NULL,
        cover_photo_id TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        score REAL NOT NULL,
        theme INTEGER NOT NULL,
        status INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_auto_generated INTEGER NOT NULL DEFAULT 1,
        location_label TEXT,
        person_ids TEXT,
        day_of_week INTEGER,
        month INTEGER,
        year INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS automatic_albums (
        album_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        type INTEGER NOT NULL,
        photo_ids TEXT NOT NULL,
        cover_photo_id TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        score REAL NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        location_label TEXT,
        year INTEGER,
        month INTEGER
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_memories_status ON memories(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_memories_score ON memories(score DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_memories_theme ON memories(theme)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_auto_albums_type ON automatic_albums(type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_auto_albums_hidden ON automatic_albums(is_hidden)');
  }

  static Future<void> _createEditRecipesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS edit_recipes (
        photo_id TEXT PRIMARY KEY,
        operations_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        is_exported INTEGER NOT NULL DEFAULT 0,
        exported_path TEXT
      )
    ''');
  }

  static Future<void> _createAnalysisTables(Database db) async {
    // Analysis state: tracks what has been computed for each photo
    await db.execute('''
      CREATE TABLE IF NOT EXISTS analysis_state (
        photo_id TEXT PRIMARY KEY,
        content_hash TEXT,
        perceptual_hash TEXT,
        blur_classification INTEGER NOT NULL DEFAULT 0,
        exposure_classification INTEGER NOT NULL DEFAULT 0,
        quality_score REAL,
        is_screenshot INTEGER,
        is_document INTEGER,
        scene_labels TEXT,
        activity_labels TEXT,
        event_id TEXT,
        analysis_version TEXT NOT NULL DEFAULT '1.0',
        analyzed_at TEXT,
        completed_stages INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Duplicate groups: groups of exact/near-duplicate photos
    await db.execute('''
      CREATE TABLE IF NOT EXISTS duplicate_groups (
        group_id TEXT PRIMARY KEY,
        photo_ids TEXT NOT NULL,
        type INTEGER NOT NULL,
        similarity REAL NOT NULL,
        confidence REAL NOT NULL,
        recommended_keep_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Photo events: clustered events from time+location+visual similarity
    await db.execute('''
      CREATE TABLE IF NOT EXISTS photo_events (
        event_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        subtitle TEXT,
        photo_ids TEXT NOT NULL,
        cover_photo_id TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        location_label TEXT,
        latitude REAL,
        longitude REAL,
        person_ids TEXT,
        confidence REAL NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Smart albums: query-based dynamic albums
    await db.execute('''
      CREATE TABLE IF NOT EXISTS smart_albums (
        album_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        category INTEGER NOT NULL,
        query_json TEXT NOT NULL DEFAULT '{}',
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // User corrections: records of user overrides to AI results
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_corrections (
        correction_id TEXT PRIMARY KEY,
        photo_id TEXT NOT NULL,
        type INTEGER NOT NULL,
        original_label TEXT NOT NULL,
        corrected_label TEXT,
        action INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Indexes for performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_content_hash ON analysis_state(content_hash)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_perceptual_hash ON analysis_state(perceptual_hash)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_event_id ON analysis_state(event_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_completed_stages ON analysis_state(completed_stages)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_duplicate_groups_type ON duplicate_groups(type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_events_start_time ON photo_events(start_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_events_location ON photo_events(latitude, longitude)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_smart_albums_category ON smart_albums(category)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_user_corrections_photo_id ON user_corrections(photo_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_user_corrections_type ON user_corrections(type)');
  }

  static Future<void> _createVideoTables(Database db) async {
    // Video segments: temporal segments within a video
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_segments (
        id TEXT PRIMARY KEY,
        video_id TEXT NOT NULL,
        start_time_ms INTEGER NOT NULL,
        end_time_ms INTEGER NOT NULL,
        representative_frame_path TEXT,
        embedding BLOB,
        labels TEXT,
        ocr_text TEXT,
        people TEXT,
        confidence REAL,
        created_at TEXT NOT NULL
      )
    ''');

    // Video analysis: per-video analysis state (beyond what photo_metadata tracks)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_analysis (
        video_id TEXT PRIMARY KEY,
        analysis_status INTEGER NOT NULL DEFAULT 0,
        total_frames_sampled INTEGER NOT NULL DEFAULT 0,
        representative_frames_json TEXT,
        scene_count INTEGER NOT NULL DEFAULT 0,
        has_audio INTEGER NOT NULL DEFAULT 0,
        transcription_status INTEGER NOT NULL DEFAULT 0,
        embedding_status INTEGER NOT NULL DEFAULT 0,
        quality_score REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (video_id) REFERENCES photo_metadata(photo_id) ON DELETE CASCADE
      )
    ''');

    // Video extracted frames: keyframes extracted for analysis
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_frames (
        id TEXT PRIMARY KEY,
        video_id TEXT NOT NULL,
        timestamp_ms INTEGER NOT NULL,
        frame_path TEXT NOT NULL,
        width INTEGER NOT NULL,
        height INTEGER NOT NULL,
        blur_score REAL,
        quality_score REAL,
        is_representative INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (video_id) REFERENCES photo_metadata(photo_id) ON DELETE CASCADE
      )
    ''');

    // Indexes for video tables
    await db.execute('CREATE INDEX IF NOT EXISTS idx_video_segments_video_id ON video_segments(video_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_video_segments_time ON video_segments(video_id, start_time_ms)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_video_segments_confidence ON video_segments(confidence DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_video_frames_video_id ON video_frames(video_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_video_frames_representative ON video_frames(video_id, is_representative)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_video_analysis_status ON video_analysis(analysis_status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_video_analysis_video_id ON video_analysis(video_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_media_type ON photo_metadata(media_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_duration ON photo_metadata(duration_seconds)');
  }

  static Future<void> _createKnowledgeGraphTables(Database db) async {
    // Knowledge graph entities: nodes representing media, people, places,
    // events, objects, and memories as interconnected graph nodes.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_graph_entities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        external_id TEXT NOT NULL,
        display_name TEXT,
        occurrence_count INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(type, external_id)
      )
    ''');

    // Knowledge graph relationships: typed edges between entities with
    // provenance tracking (evidence source, confidence, analysis version).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_graph_relationships (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        relation_type TEXT NOT NULL,
        source_entity_id TEXT NOT NULL,
        target_entity_id TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 1.0,
        evidence_source TEXT NOT NULL,
        evidence_detail TEXT,
        analysis_version TEXT NOT NULL DEFAULT '1.0',
        weight INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(relation_type, source_entity_id, target_entity_id)
      )
    ''');

    // Indexes for graph queries
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kge_type ON knowledge_graph_entities(type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kge_external_id ON knowledge_graph_entities(external_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kge_type_external ON knowledge_graph_entities(type, external_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kge_occurrence ON knowledge_graph_entities(occurrence_count DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kgr_relation ON knowledge_graph_relationships(relation_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kgr_source ON knowledge_graph_relationships(source_entity_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kgr_target ON knowledge_graph_relationships(target_entity_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kgr_source_type ON knowledge_graph_relationships(source_entity_id, relation_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kgr_target_type ON knowledge_graph_relationships(target_entity_id, relation_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kgr_confidence ON knowledge_graph_relationships(confidence DESC)');
  }

  static Future<void> _createPhase28Indexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_jobs_priority ON ai_jobs(priority DESC, created_at ASC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_jobs_status_priority ON ai_jobs(status, priority DESC, created_at ASC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_people_status ON people(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_indexed_at ON photo_metadata(indexed_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_photo_metadata_date_created_media ON photo_metadata(date_created, media_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_photo_id ON analysis_state(photo_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_state_analyzed_at ON analysis_state(analyzed_at)');
  }
}
