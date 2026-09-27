import 'package:sqflite/sqflite.dart';

import '../../../domain/models/smart_album.dart';

/// Data access object for the smart_albums table.
class SmartAlbumDao {
  const SmartAlbumDao(this._db);

  final Database _db;

  /// Upsert a smart album.
  Future<void> upsert(SmartAlbum album) async {
    await _db.insert(
      'smart_albums',
      _toRow(album),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all visible smart albums, ordered by sort order.
  Future<List<SmartAlbum>> getAll() async {
    final rows = await _db.query(
      'smart_albums',
      where: 'is_hidden = 0',
      orderBy: 'sort_order ASC, title ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Get all smart albums including hidden ones.
  Future<List<SmartAlbum>> getAllIncludingHidden() async {
    final rows = await _db.query('smart_albums', orderBy: 'sort_order ASC');
    return rows.map(_fromRow).toList();
  }

  /// Get a smart album by ID.
  Future<SmartAlbum?> getById(String albumId) async {
    final rows = await _db.query(
      'smart_albums',
      where: 'album_id = ?',
      whereArgs: [albumId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Get smart albums by category.
  Future<List<SmartAlbum>> getByCategory(SmartAlbumCategory category) async {
    final rows = await _db.query(
      'smart_albums',
      where: 'category = ?',
      whereArgs: [category.index],
      orderBy: 'sort_order ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Hide a smart album.
  Future<void> hide(String albumId) async {
    await _db.update(
      'smart_albums',
      {'is_hidden': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
  }

  /// Unhide a smart album.
  Future<void> unhide(String albumId) async {
    await _db.update(
      'smart_albums',
      {'is_hidden': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
  }

  /// Delete a smart album.
  Future<void> deleteById(String albumId) async {
    await _db.delete('smart_albums', where: 'album_id = ?', whereArgs: [albumId]);
  }

  /// Count visible smart albums.
  Future<int> count() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as c FROM smart_albums WHERE is_hidden = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Map<String, Object?> _toRow(SmartAlbum a) => {
        'album_id': a.albumId,
        'title': a.title,
        'category': a.category.index,
        'query_json': a.query.toJson(),
        'sort_order': a.sortOrder,
        'is_hidden': a.isHidden ? 1 : 0,
        'created_at': a.createdAt.toIso8601String(),
        'updated_at': a.updatedAt.toIso8601String(),
      };

  SmartAlbum _fromRow(Map<String, Object?> row) => SmartAlbum(
        albumId: row['album_id'] as String,
        title: row['title'] as String,
        category: SmartAlbumCategory.values[row['category'] as int],
        query: SmartAlbumQuery.fromJson(row['query_json'] as String? ?? '{}'),
        sortOrder: row['sort_order'] as int? ?? 0,
        isHidden: (row['is_hidden'] as int?) == 1,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}
