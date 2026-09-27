import 'package:sqflite/sqflite.dart';

/// Visibility modes for photos (Ente-style organization).
enum VisibilityMode {
  /// Decluttered from the timeline but still visible in albums and search.
  archived,

  /// Excluded from timeline, albums, and search. Viewing requires the
  /// Hidden PIN.
  hidden,
}

/// DAO for per-photo visibility modes.
class VisibilityDao {
  VisibilityDao(this._db);

  final Database _db;

  static const String tableName = 'visibility';

  /// Set [mode] for [photoId] (replaces any previous mode).
  Future<void> setMode(String photoId, VisibilityMode mode) async {
    await _db.insert(
      tableName,
      {'photo_id': photoId, 'mode': mode.name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Clear any visibility mode (back to normal).
  Future<void> clearMode(String photoId) async {
    await _db.delete(
      tableName,
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
  }

  /// Current mode, or null for normal visibility.
  Future<VisibilityMode?> modeOf(String photoId) async {
    final rows = await _db.query(
      tableName,
      columns: ['mode'],
      where: 'photo_id = ?',
      whereArgs: [photoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final name = rows.first['mode'] as String;
    return VisibilityMode.values.asNameMap()[name];
  }

  /// All photo IDs in [mode].
  Future<Set<String>> idsInMode(VisibilityMode mode) async {
    final rows = await _db.query(
      tableName,
      columns: ['photo_id'],
      where: 'mode = ?',
      whereArgs: [mode.name],
    );
    return rows.map((r) => r['photo_id'] as String).toSet();
  }
}
