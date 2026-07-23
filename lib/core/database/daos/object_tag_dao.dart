import 'package:ai_gallery/domain/models/object_detection.dart';
import 'package:sqflite/sqflite.dart';

/// DAO for object detection tags.
class ObjectTagDao {
  ObjectTagDao(this._db);

  final Database _db;

  static const String tableName = 'object_tags';

  /// Insert an object tag.
  Future<void> insertObjectTag(ObjectTagRecord tag) async {
    await _db.insert(
      tableName,
      tag.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert multiple object tags in a batch.
  Future<void> insertObjectTags(List<ObjectTagRecord> tags) async {
    final batch = _db.batch();
    for (final tag in tags) {
      batch.insert(
        tableName,
        tag.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get object tags by photo ID.
  Future<List<ObjectTagRecord>> getObjectTagsByPhotoId(String photoId) async {
    final rows = await _db.query(
      tableName,
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
    return rows.map(ObjectTagRecord.fromMap).toList();
  }

  /// Delete object tags by photo ID.
  Future<void> deleteObjectTagsByPhotoId(String photoId) async {
    await _db.delete(
      tableName,
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
  }

  /// Get top object labels across all photos.
  Future<Map<String, int>> getTopLabels({int limit = 20}) async {
    final rows = await _db.rawQuery('''
      SELECT label, COUNT(*) as count
      FROM $tableName
      GROUP BY label
      ORDER BY count DESC
      LIMIT ?
    ''', [limit]);
    return {for (var row in rows) row['label'] as String: row['count'] as int};
  }
}