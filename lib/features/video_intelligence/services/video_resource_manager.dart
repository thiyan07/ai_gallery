import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';

/// Manages video-related resources: disk cleanup, frame cache, old data pruning.
///
/// Called periodically or on-demand to prevent unbounded disk growth.
class VideoResourceManager {
  VideoResourceManager({
    required AppDatabase database,
    required AppLogger logger,
  })  : _db = database,
        _logger = logger;

  final AppDatabase _db;
  final AppLogger _logger;

  /// Get current disk usage for all video resources.
  Future<VideoDiskUsage> getDiskUsage() async {
    var frameBytes = 0;
    var frameCount = 0;

    final frames = await _db.database.rawQuery(
      'SELECT frame_path FROM video_frames WHERE frame_path IS NOT NULL',
    );
    for (final row in frames) {
      final path = row['frame_path'] as String;
      final file = File(path);
      if (await file.exists()) {
        frameBytes += await file.length();
        frameCount++;
      }
    }

    final segmentCount = await _db.videoSegments.count();
    final analysisCount = await _db.videoAnalysis.countAnalyzed();

    return VideoDiskUsage(
      frameBytes: frameBytes,
      frameCount: frameCount,
      segmentCount: segmentCount,
      analyzedVideoCount: analysisCount,
    );
  }

  /// Clean up orphaned frames (frames whose files no longer exist).
  Future<int> cleanOrphanedFrames() async {
    final rows = await _db.database.rawQuery(
      'SELECT id, frame_path FROM video_frames WHERE frame_path IS NOT NULL',
    );

    var deletedCount = 0;
    for (final row in rows) {
      final path = row['frame_path'] as String;
      final file = File(path);
      if (!await file.exists()) {
        await _db.database.delete(
          'video_frames',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        deletedCount++;
      }
    }

    if (deletedCount > 0) {
      _logger.info('Cleaned up $deletedCount orphaned video frames');
    }
    return deletedCount;
  }

  /// Clean up old video frame files (older than [maxAge]).
  Future<int> cleanOldFrameFiles({Duration maxAge = const Duration(days: 30)}) async {
    final tempDir = await getTemporaryDirectory();
    final framesDir = Directory('${tempDir.path}/video_frames');
    if (!await framesDir.exists()) return 0;

    var deletedCount = 0;
    final cutoff = DateTime.now().subtract(maxAge);

    await for (final entity in framesDir.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
          deletedCount++;
        }
      }
    }

    if (deletedCount > 0) {
      _logger.info('Cleaned up $deletedCount old video frame files');
    }
    return deletedCount;
  }

  /// Full cleanup: orphaned frames + old files + stale analysis records.
  Future<VideoCleanupResult> performCleanup({
    Duration maxFrameAge = const Duration(days: 30),
  }) async {
    final orphaned = await cleanOrphanedFrames();
    final oldFiles = await cleanOldFrameFiles(maxAge: maxFrameAge);

    // Clean up video_analysis records for videos that no longer exist
    final staleAnalysis = await _db.database.rawQuery('''
      SELECT va.video_id
      FROM video_analysis va
      LEFT JOIN photo_metadata pm ON va.video_id = pm.photo_id
      WHERE pm.photo_id IS NULL
    ''');
    for (final row in staleAnalysis) {
      final videoId = row['video_id'] as String;
      await _db.videoAnalysis.deleteByVideoId(videoId);
      await _db.videoFrames.deleteByVideoId(videoId);
      await _db.videoSegments.deleteByVideoId(videoId);
    }

    if (staleAnalysis.isNotEmpty) {
      _logger.info(
        'Cleaned up ${staleAnalysis.length} stale video analysis records',
      );
    }

    return VideoCleanupResult(
      orphanedFramesRemoved: orphaned,
      oldFrameFilesRemoved: oldFiles,
      staleAnalysisRecordsRemoved: staleAnalysis.length,
    );
  }
}

/// Disk usage breakdown for video resources.
class VideoDiskUsage {
  final int frameBytes;
  final int frameCount;
  final int segmentCount;
  final int analyzedVideoCount;

  const VideoDiskUsage({
    required this.frameBytes,
    required this.frameCount,
    required this.segmentCount,
    required this.analyzedVideoCount,
  });

  String get frameBytesFormatted {
    if (frameBytes < 1024) return '${frameBytes}B';
    if (frameBytes < 1024 * 1024) return '${(frameBytes / 1024).toStringAsFixed(1)}KB';
    return '${(frameBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  Map<String, dynamic> toMap() => {
        'frame_bytes': frameBytes,
        'frame_bytes_formatted': frameBytesFormatted,
        'frame_count': frameCount,
        'segment_count': segmentCount,
        'analyzed_video_count': analyzedVideoCount,
      };
}

/// Result of a cleanup operation.
class VideoCleanupResult {
  final int orphanedFramesRemoved;
  final int oldFrameFilesRemoved;
  final int staleAnalysisRecordsRemoved;

  const VideoCleanupResult({
    required this.orphanedFramesRemoved,
    required this.oldFrameFilesRemoved,
    required this.staleAnalysisRecordsRemoved,
  });

  int get totalRemoved =>
      orphanedFramesRemoved +
      oldFrameFilesRemoved +
      staleAnalysisRecordsRemoved;

  Map<String, dynamic> toMap() => {
        'orphaned_frames_removed': orphanedFramesRemoved,
        'old_frame_files_removed': oldFrameFilesRemoved,
        'stale_analysis_records_removed': staleAnalysisRecordsRemoved,
        'total_removed': totalRemoved,
      };
}
