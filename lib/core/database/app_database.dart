import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../errors/app_exception.dart' as app_exceptions;
import '../logging/app_logger.dart';
import 'daos/ai_job_dao.dart';
import 'daos/embedding_dao.dart';
import 'daos/face_dao.dart';
import 'daos/favorites_dao.dart';
import 'daos/object_tag_dao.dart';
import 'daos/ocr_dao.dart';
import 'daos/photo_metadata_dao.dart';

/// Central SQLite database for AI Gallery metadata.
class AppDatabase {
  AppDatabase._(this._db);

  static AppDatabase? _instance;
  static const _dbName = 'ai_gallery.db';
  static const _dbVersion = 4;

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

  /// Opens or returns the singleton database instance.
  static Future<AppDatabase> open({AppLogger? logger}) async {
    if (_instance != null) return _instance!;

    try {
      final dbPath = await getDatabasesPath();
      final db = await openDatabase(
        join(dbPath, _dbName),
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      _instance = AppDatabase._(db);
      logger?.info('AppDatabase opened at ${join(dbPath, _dbName)}');
      return _instance!;
    } catch (e, st) {
      logger?.error('Failed to open AppDatabase', error: e, stackTrace: st);
      throw app_exceptions.DatabaseException(
        'Failed to open database',
        cause: e,
      );
    }
  }

  /// Closes the database and clears the singleton (for tests).
  static Future<void> closeForTesting() async {
    await _instance?._db.close();
    _instance = null;
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
    if (oldVersion < 4) {
      await _createPhotoUsageTable(db);
    }
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
        label TEXT,
        embedding BLOB
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS object_tags (
        id TEXT PRIMARY KEY,
        photo_id TEXT NOT NULL,
        label TEXT NOT NULL,
        confidence REAL NOT NULL
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
        bounding_box_height REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS embeddings (
        id TEXT PRIMARY KEY,
        photo_id TEXT NOT NULL,
        model TEXT NOT NULL,
        vector BLOB NOT NULL,
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
        completed_at TEXT
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
        media_type TEXT
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

  static Future<void> _createIndexStatusTable(Database db) async {
    await db.execute('''
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
}
