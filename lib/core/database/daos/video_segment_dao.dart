import 'package:uuid/uuid.dart';

import '../../../domain/models/video_segment.dart';
import '../../../core/logging/app_logger.dart';

/// DAO for the video_segments table.
class VideoSegmentDao {
  VideoSegmentDao(this._db, {AppLogger? logger}) : _logger = logger;

  final dynamic _db;
  final AppLogger? _logger;
  static const _uuid = Uuid();

  Future<void> upsert(VideoSegment segment) async {
    await _db.insert(
      'video_segments',
      segment.toMap(),
      conflictAlgorithm: 4, // ConflictAlgorithm.replace
    );
  }

  Future<List<VideoSegment>> getByVideoId(String videoId) async {
    final rows = await _db.query(
      'video_segments',
      where: 'video_id = ?',
      whereArgs: [videoId],
      orderBy: 'start_time_ms ASC',
    );
    return rows.map(VideoSegment.fromMap).toList();
  }

  Future<List<VideoSegment>> searchByLabel(String label) async {
    final rows = await _db.rawQuery(
      "SELECT * FROM video_segments WHERE labels LIKE ? ORDER BY confidence DESC",
      ['%$label%'],
    );
    return rows.map(VideoSegment.fromMap).toList();
  }

  Future<List<VideoSegment>> searchByOcr(String query) async {
    final rows = await _db.rawQuery(
      "SELECT * FROM video_segments WHERE ocr_text LIKE ? ORDER BY confidence DESC",
      ['%$query%'],
    );
    return rows.map(VideoSegment.fromMap).toList();
  }

  Future<List<VideoSegment>> searchByPerson(String personId) async {
    final rows = await _db.rawQuery(
      "SELECT * FROM video_segments WHERE people LIKE ? ORDER BY confidence DESC",
      ['%$personId%'],
    );
    return rows.map(VideoSegment.fromMap).toList();
  }

  Future<void> deleteByVideoId(String videoId) async {
    await _db.delete(
      'video_segments',
      where: 'video_id = ?',
      whereArgs: [videoId],
    );
  }

  Future<int> countForVideo(String videoId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as c FROM video_segments WHERE video_id = ?',
      [videoId],
    );
    return result.first['c'] as int;
  }

  Future<int> count() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as c FROM video_segments',
    );
    return result.first['c'] as int;
  }

  static String newId() => _uuid.v4();
}
