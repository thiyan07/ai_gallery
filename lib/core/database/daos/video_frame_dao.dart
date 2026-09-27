import 'package:uuid/uuid.dart';

import '../../../domain/models/video_frame.dart';
import '../../../core/logging/app_logger.dart';

/// DAO for the video_frames table.
class VideoFrameDao {
  VideoFrameDao(this._db, {AppLogger? logger}) : _logger = logger;

  final dynamic _db;
  final AppLogger? _logger;
  static const _uuid = Uuid();

  Future<void> upsert(VideoFrame frame) async {
    await _db.insert(
      'video_frames',
      frame.toMap(),
      conflictAlgorithm: 4, // ConflictAlgorithm.replace
    );
  }

  Future<List<VideoFrame>> getByVideoId(String videoId) async {
    final rows = await _db.query(
      'video_frames',
      where: 'video_id = ?',
      whereArgs: [videoId],
      orderBy: 'timestamp_ms ASC',
    );
    return rows.map(VideoFrame.fromMap).toList();
  }

  Future<List<VideoFrame>> getRepresentativeFrames(String videoId) async {
    final rows = await _db.query(
      'video_frames',
      where: 'video_id = ? AND is_representative = 1',
      whereArgs: [videoId],
      orderBy: 'timestamp_ms ASC',
    );
    return rows.map(VideoFrame.fromMap).toList();
  }

  Future<void> markAsRepresentative(String frameId, bool isRepresentative) async {
    await _db.update(
      'video_frames',
      {'is_representative': isRepresentative ? 1 : 0},
      where: 'id = ?',
      whereArgs: [frameId],
    );
  }

  Future<void> deleteByVideoId(String videoId) async {
    await _db.delete(
      'video_frames',
      where: 'video_id = ?',
      whereArgs: [videoId],
    );
  }

  Future<int> countForVideo(String videoId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as c FROM video_frames WHERE video_id = ?',
      [videoId],
    );
    return result.first['c'] as int;
  }

  static String newId() => _uuid.v4();
}
