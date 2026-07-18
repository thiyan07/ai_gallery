import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite-backed service for persisting photo favorites.
class FavoritesService {
  static Database? _db;

  /// Opens (or creates) the database.
  static Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'ai_gallery.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE favorites (
            asset_id TEXT PRIMARY KEY,
            added_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// Adds a photo to favorites.
  static Future<void> add(String assetId) async {
    final db = await _getDb();
    await db.insert(
      'favorites',
      {'asset_id': assetId, 'added_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes a photo from favorites.
  static Future<void> remove(String assetId) async {
    final db = await _getDb();
    await db.delete('favorites', where: 'asset_id = ?', whereArgs: [assetId]);
  }

  /// Returns all favorited asset IDs.
  static Future<Set<String>> getAllFavoriteIds() async {
    final db = await _getDb();
    final rows = await db.query('favorites');
    return rows.map((r) => r['asset_id'] as String).toSet();
  }

  /// Checks if a photo is favorited.
  static Future<bool> isFavorite(String assetId) async {
    final db = await _getDb();
    final rows = await db.query(
      'favorites',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
