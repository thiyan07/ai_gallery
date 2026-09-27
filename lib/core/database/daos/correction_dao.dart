import 'package:sqflite/sqflite.dart';

import '../../../domain/models/user_correction.dart';

/// Data access object for the user_corrections table.
class CorrectionDao {
  const CorrectionDao(this._db);

  final Database _db;

  /// Insert a new correction.
  Future<void> insert(UserCorrection correction) async {
    await _db.insert('user_corrections', _toRow(correction));
  }

  /// Get all corrections for a photo.
  Future<List<UserCorrection>> getByPhotoId(String photoId) async {
    final rows = await _db.query(
      'user_corrections',
      where: 'photo_id = ?',
      whereArgs: [photoId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Get all corrections of a specific type.
  Future<List<UserCorrection>> getByType(CorrectionType type) async {
    final rows = await _db.query(
      'user_corrections',
      where: 'type = ?',
      whereArgs: [type.index],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Check if a specific label has been corrected for a photo.
  Future<bool> hasCorrection(
    String photoId,
    CorrectionType type,
    String originalLabel,
  ) async {
    final rows = await _db.query(
      'user_corrections',
      where: 'photo_id = ? AND type = ? AND original_label = ?',
      whereArgs: [photoId, type.index, originalLabel],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Get all removed labels for a photo (used to suppress future results).
  Future<List<String>> getRemovedLabels(
    String photoId,
    CorrectionType type,
  ) async {
    final rows = await _db.query(
      'user_corrections',
      columns: ['original_label'],
      where: 'photo_id = ? AND type = ? AND action = ?',
      whereArgs: [photoId, type.index, CorrectionAction.removeLabel.index],
    );
    return rows.map((r) => r['original_label'] as String).toList();
  }

  /// Get all globally removed labels for a type (cross-photo suppression).
  Future<Set<String>> getGlobalRemovedLabels(CorrectionType type) async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT original_label FROM user_corrections '
      'WHERE type = ? AND action = ?',
      [type.index, CorrectionAction.removeLabel.index],
    );
    return rows.map((r) => r['original_label'] as String).toSet();
  }

  /// Delete all corrections for a photo.
  Future<void> deleteByPhotoId(String photoId) async {
    await _db.delete('user_corrections', where: 'photo_id = ?', whereArgs: [photoId]);
  }

  /// Count total corrections.
  Future<int> count() async {
    final result =
        await _db.rawQuery('SELECT COUNT(*) as c FROM user_corrections');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Map<String, Object?> _toRow(UserCorrection c) => {
        'correction_id': c.correctionId,
        'photo_id': c.photoId,
        'type': c.type.index,
        'original_label': c.originalLabel,
        'corrected_label': c.correctedLabel,
        'action': c.action.index,
        'created_at': c.createdAt.toIso8601String(),
      };

  UserCorrection _fromRow(Map<String, Object?> row) => UserCorrection(
        correctionId: row['correction_id'] as String,
        photoId: row['photo_id'] as String,
        type: CorrectionType.values[row['type'] as int],
        originalLabel: row['original_label'] as String,
        correctedLabel: row['corrected_label'] as String?,
        action: CorrectionAction.values[row['action'] as int],
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}
