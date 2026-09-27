import '../../../domain/models/video_analysis.dart';
import '../../../core/logging/app_logger.dart';

/// DAO for the video_analysis table.
class VideoAnalysisDao {
  VideoAnalysisDao(this._db, {AppLogger? logger}) : _logger = logger;

  final dynamic _db;
  final AppLogger? _logger;

  Future<void> upsert(VideoAnalysis analysis) async {
    await _db.insert(
      'video_analysis',
      analysis.toMap(),
      conflictAlgorithm: 4, // ConflictAlgorithm.replace
    );
  }

  Future<VideoAnalysis?> getByVideoId(String videoId) async {
    final rows = await _db.query(
      'video_analysis',
      where: 'video_id = ?',
      whereArgs: [videoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VideoAnalysis.fromMap(rows.first);
  }

  Future<List<VideoAnalysis>> getByStatus(VideoAnalysisStatus status) async {
    final rows = await _db.query(
      'video_analysis',
      where: 'analysis_status = ?',
      whereArgs: [status.index],
      orderBy: 'created_at ASC',
    );
    return rows.map(VideoAnalysis.fromMap).toList();
  }

  Future<List<String>> getUnanalyzedVideoIds() async {
    final rows = await _db.rawQuery(
      "SELECT video_id FROM video_analysis WHERE analysis_status = 0",
    );
    return rows.map((r) => r['video_id'] as String).toList();
  }

  Future<List<String>> getVideoIdsNeedingEmbedding() async {
    final rows = await _db.rawQuery(
      "SELECT video_id FROM video_analysis WHERE embedding_status = 0 AND analysis_status != 5",
    );
    return rows.map((r) => r['video_id'] as String).toList();
  }

  Future<void> updateStatus(String videoId, VideoAnalysisStatus status) async {
    await _db.update(
      'video_analysis',
      {
        'analysis_status': status.index,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'video_id = ?',
      whereArgs: [videoId],
    );
  }

  Future<void> deleteByVideoId(String videoId) async {
    await _db.delete(
      'video_analysis',
      where: 'video_id = ?',
      whereArgs: [videoId],
    );
  }

  Future<int> countByStatus(VideoAnalysisStatus status) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as c FROM video_analysis WHERE analysis_status = ?',
      [status.index],
    );
    return result.first['c'] as int;
  }

  /// Count videos that have completed analysis (status != pending).
  Future<int> countAnalyzed() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as c FROM video_analysis WHERE analysis_status > 0',
    );
    return result.first['c'] as int;
  }
}
