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
    final rows = await _db.rawQuery(
      'SELECT label, COUNT(*) as count '
      'FROM $tableName '
      'GROUP BY label '
      'ORDER BY count DESC '
      'LIMIT ?',
      [limit],
    );
    return {for (var row in rows) row['label'] as String: row['count'] as int};
  }

  /// Find photo IDs that contain any of the specified object labels.
  ///
  /// Returns photo IDs that have at least one matching label, with the
  /// highest confidence score per photo.
  Future<Map<String, double>> searchByLabels(
    List<String> labels, {
    double minConfidence = 0.3,
  }) async {
    if (labels.isEmpty) return {};

    final placeholders = labels.map((_) => '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT photo_id, MAX(confidence) as max_confidence '
      'FROM $tableName '
      'WHERE label IN ($placeholders) AND confidence >= ? '
      'GROUP BY photo_id',
      [...labels, minConfidence],
    );

    return {
      for (var row in rows)
        row['photo_id'] as String:
            (row['max_confidence'] as num).toDouble(),
    };
  }

  /// Find photo IDs that contain ALL of the specified object labels (AND).
  Future<List<String>> searchByAllLabels(
    List<String> labels, {
    double minConfidence = 0.3,
  }) async {
    if (labels.isEmpty) return [];

    final placeholders = labels.map((_) => '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT photo_id, COUNT(DISTINCT label) as matched_labels '
      'FROM $tableName '
      'WHERE label IN ($placeholders) AND confidence >= ? '
      'GROUP BY photo_id '
      'HAVING matched_labels = ?',
      [...labels, minConfidence, labels.length],
    );

    return rows.map((row) => row['photo_id'] as String).toList();
  }

  /// Find photo IDs that contain NONE of the specified labels.
  Future<List<String>> excludeLabels(
    List<String> excludeLabels, {
    List<String>? requireAnyLabel,
    double minConfidence = 0.3,
  }) async {
    if (excludeLabels.isEmpty) return [];

    final placeholders = excludeLabels.map((_) => '?').join(',');

    final excludedRows = await _db.rawQuery(
      'SELECT DISTINCT photo_id '
      'FROM $tableName '
      'WHERE label IN ($placeholders) AND confidence >= ?',
      [...excludeLabels, minConfidence],
    );

    final excludedIds =
        excludedRows.map((row) => row['photo_id'] as String).toSet();

    if (excludedIds.isEmpty) return [];

    List<String> allPhotoIds;
    if (requireAnyLabel != null && requireAnyLabel.isNotEmpty) {
      final reqPlaceholders = requireAnyLabel.map((_) => '?').join(',');
      final allRows = await _db.rawQuery(
        'SELECT DISTINCT photo_id '
        'FROM $tableName '
        'WHERE label IN ($reqPlaceholders) AND confidence >= ?',
        [...requireAnyLabel, minConfidence],
      );
      allPhotoIds =
          allRows.map((row) => row['photo_id'] as String).toList();
    } else {
      final allRows = await _db.rawQuery(
        'SELECT DISTINCT photo_id FROM $tableName',
      );
      allPhotoIds =
          allRows.map((row) => row['photo_id'] as String).toList();
    }

    return allPhotoIds.where((id) => !excludedIds.contains(id)).toList();
  }
}
