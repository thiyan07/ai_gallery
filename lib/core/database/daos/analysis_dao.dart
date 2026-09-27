import 'package:sqflite/sqflite.dart';

import '../../../domain/models/analysis_state.dart';

/// Data access object for the analysis_state table.
class AnalysisDao {
  const AnalysisDao(this._db);

  final Database _db;

  /// Get analysis state for a photo.
  Future<AnalysisState?> getByPhotoId(String photoId) async {
    final rows = await _db.query(
      'analysis_state',
      where: 'photo_id = ?',
      whereArgs: [photoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AnalysisState.fromMap(rows.first);
  }

  /// Upsert analysis state.
  Future<void> upsert(AnalysisState state) async {
    await _db.insert(
      'analysis_state',
      state.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Batch upsert analysis states.
  Future<void> upsertAll(List<AnalysisState> states) async {
    final batch = _db.batch();
    for (final state in states) {
      batch.insert(
        'analysis_state',
        state.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get all photos that need analysis for a given stage.
  Future<List<AnalysisState>> getPhotosNeedingStage(
    AnalysisStage stage, {
    int limit = 100,
  }) async {
    final rows = await _db.query(
      'analysis_state',
      where: 'completed_stages & ? = 0',
      whereArgs: [stage.mask],
      limit: limit,
    );
    return rows.map(AnalysisState.fromMap).toList();
  }

  /// Get all photos that haven't been analyzed yet (no row in analysis_state).
  Future<List<String>> getUnanalyzedPhotoIds({int limit = 100}) async {
    final rows = await _db.rawQuery(
      'SELECT p.id FROM photos p '
      'LEFT JOIN analysis_state a ON p.id = a.photo_id '
      'WHERE a.photo_id IS NULL '
      'LIMIT ?',
      [limit],
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  /// Look up photo IDs by content hash.
  Future<List<String>> getByContentHash(String contentHash) async {
    final rows = await _db.query(
      'analysis_state',
      columns: ['photo_id'],
      where: 'content_hash = ?',
      whereArgs: [contentHash],
    );
    return rows.map((r) => r['photo_id'] as String).toList();
  }

  /// Look up photo IDs by perceptual hash.
  Future<List<String>> getByPerceptualHash(String perceptualHash) async {
    final rows = await _db.query(
      'analysis_state',
      columns: ['photo_id'],
      where: 'perceptual_hash = ?',
      whereArgs: [perceptualHash],
    );
    return rows.map((r) => r['photo_id'] as String).toList();
  }

  /// Get all photos with a specific event ID.
  Future<List<AnalysisState>> getByEventId(String eventId) async {
    final rows = await _db.query(
      'analysis_state',
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
    return rows.map(AnalysisState.fromMap).toList();
  }

  /// Set event ID for multiple photos.
  Future<void> setEventIds(List<String> photoIds, String eventId) async {
    final batch = _db.batch();
    for (final photoId in photoIds) {
      batch.update(
        'analysis_state',
        {'event_id': eventId},
        where: 'photo_id = ?',
        whereArgs: [photoId],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Count total analyzed photos.
  Future<int> countAnalyzed() async {
    final result = await _db
        .rawQuery('SELECT COUNT(*) as c FROM analysis_state');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete analysis state for a photo.
  Future<void> deleteByPhotoId(String photoId) async {
    await _db.delete('analysis_state', where: 'photo_id = ?', whereArgs: [photoId]);
  }

  /// Watch analysis progress as a stream.
  Stream<int> watchAnalyzedCount() {
    return _db
        .rawQuery('SELECT COUNT(*) as c FROM analysis_state')
        .asStream()
        .map((rows) => Sqflite.firstIntValue(rows) ?? 0);
  }

  /// Get photo IDs grouped by content hash (for exact duplicate detection).
  Future<List<Map<String, Object?>>> getGroupedByContentHash() async {
    return _db.rawQuery(
      'SELECT content_hash, GROUP_CONCAT(photo_id) as photo_ids '
      'FROM analysis_state '
      'WHERE content_hash IS NOT NULL AND content_hash != "" '
      'GROUP BY content_hash '
      'HAVING COUNT(*) > 1',
    );
  }

  /// Get all photo IDs and their perceptual hashes.
  Future<List<Map<String, Object?>>> getAllPerceptualHashes() async {
    return _db.rawQuery(
      'SELECT photo_id, perceptual_hash FROM analysis_state '
      'WHERE perceptual_hash IS NOT NULL AND perceptual_hash != ""',
    );
  }

  /// Get photo metadata (date, location) for event clustering.
  Future<List<Map<String, Object?>>> getPhotoTimeAndLocation() async {
    return _db.rawQuery(
      'SELECT pm.photo_id as id, pm.date_created as date_taken, pm.latitude, pm.longitude '
      'FROM photo_metadata pm '
      'WHERE pm.date_created IS NOT NULL '
      'ORDER BY pm.date_created ASC',
    );
  }
}
