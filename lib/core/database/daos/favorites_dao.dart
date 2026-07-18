import 'package:sqflite/sqflite.dart';

/// Data access object for the favorites table.
class FavoritesDao {
  const FavoritesDao(this._db);

  final Database _db;

  /// Adds a photo to favorites.
  Future<void> add(String assetId) async {
    await _db.insert(
      'favorites',
      {'asset_id': assetId, 'added_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes a photo from favorites.
  Future<void> remove(String assetId) async {
    await _db.delete(
      'favorites',
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
  }

  /// Returns all favorited asset IDs.
  Future<Set<String>> getAllIds() async {
    final rows = await _db.query('favorites');
    return rows.map((r) => r['asset_id'] as String).toSet();
  }

  /// Checks if a photo is favorited.
  Future<bool> isFavorite(String assetId) async {
    final rows = await _db.query(
      'favorites',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
