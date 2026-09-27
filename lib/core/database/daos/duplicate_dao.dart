import 'package:sqflite/sqflite.dart';

import '../../../domain/models/duplicate_group.dart';

/// Data access object for the duplicate_groups table.
class DuplicateDao {
  const DuplicateDao(this._db);

  final Database _db;

  /// Upsert a duplicate group.
  Future<void> upsert(DuplicateGroup group) async {
    await _db.insert(
      'duplicate_groups',
      _toRow(group),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all duplicate groups.
  Future<List<DuplicateGroup>> getAll() async {
    final rows = await _db.query(
      'duplicate_groups',
      orderBy: 'similarity DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Get a duplicate group by ID.
  Future<DuplicateGroup?> getById(String groupId) async {
    final rows = await _db.query(
      'duplicate_groups',
      where: 'group_id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Get all groups that contain a specific photo.
  Future<List<DuplicateGroup>> getByPhotoId(String photoId) async {
    final rows = await _db.query(
      'duplicate_groups',
      where: 'photo_ids LIKE ?',
      whereArgs: ['%$photoId%'],
    );
    return rows.map(_fromRow).toList();
  }

  /// Get groups by type.
  Future<List<DuplicateGroup>> getByType(DuplicateType type) async {
    final rows = await _db.query(
      'duplicate_groups',
      where: 'type = ?',
      whereArgs: [type.index],
      orderBy: 'similarity DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Delete a duplicate group.
  Future<void> deleteById(String groupId) async {
    await _db.delete('duplicate_groups', where: 'group_id = ?', whereArgs: [groupId]);
  }

  /// Delete all groups (for re-clustering).
  Future<void> deleteAll() async {
    await _db.delete('duplicate_groups');
  }

  /// Count total groups.
  Future<int> count() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as c FROM duplicate_groups');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Count total duplicate photos (photos that appear in any group).
  Future<int> countDuplicatePhotos() async {
    final result = await _db.rawQuery(
      "SELECT COUNT(DISTINCT photo_id) as c FROM ("
      "SELECT photo_id FROM duplicate_groups, "
      "json_each('[' || photo_ids || ']') WHERE type != 0)",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Watch duplicate group count.
  Stream<int> watchCount() {
    return _db
        .rawQuery('SELECT COUNT(*) as c FROM duplicate_groups')
        .asStream()
        .map((rows) => Sqflite.firstIntValue(rows) ?? 0);
  }

  Map<String, Object?> _toRow(DuplicateGroup g) => {
        'group_id': g.groupId,
        'photo_ids': g.photoIds.join(','),
        'type': g.type.index,
        'similarity': g.similarity,
        'confidence': g.confidence,
        'recommended_keep_id': g.recommendedKeepId,
        'created_at': g.createdAt.toIso8601String(),
        'updated_at': g.updatedAt.toIso8601String(),
      };

  DuplicateGroup _fromRow(Map<String, Object?> row) => DuplicateGroup(
        groupId: row['group_id'] as String,
        photoIds: (row['photo_ids'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
        type: DuplicateType.values[row['type'] as int],
        similarity: row['similarity'] as double,
        confidence: row['confidence'] as double,
        recommendedKeepId: row['recommended_keep_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}
