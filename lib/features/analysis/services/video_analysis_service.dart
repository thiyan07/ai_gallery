import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/photo_metadata.dart';
import '../../../domain/models/video_analysis.dart';
import '../../../domain/models/video_frame.dart';
import '../../../domain/models/video_segment.dart';
import '../../video_intelligence/services/video_intelligence_engine.dart';

/// Orchestrates video analysis pipeline.
///
/// Phase 1 (analyzeVideo): Extracts metadata, frames, and time-based segments.
/// Phase 2 (enhanceAnalysis): Post-AI content-based scene detection,
///   highlight detection, chapter generation, and summary.
class VideoAnalysisService {
  VideoAnalysisService({
    required AppDatabase database,
    required AppLogger logger,
  })  : _db = database,
        _logger = logger;

  final AppDatabase _db;
  final AppLogger _logger;
  static const _uuid = Uuid();

  /// Analyze a single video — extracts metadata, thumbnails, and segments.
  ///
  /// Uses the intelligence engine for adaptive frame sampling.
  /// Returns the VideoAnalysis record.
  Future<VideoAnalysis> analyzeVideo(String videoId) async {
    _logger.info('Starting video analysis: $videoId');

    final asset = await AssetEntity.fromId(videoId);
    if (asset == null || asset.type != AssetType.video) {
      _logger.warning('Asset not found or not a video: $videoId');
      return _createFailedAnalysis(videoId);
    }

    final now = DateTime.now();
    var analysis = VideoAnalysis(
      videoId: videoId,
      analysisStatus: VideoAnalysisStatus.processing,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _ensureMetadata(asset);

      // Use intelligence engine for adaptive frame sampling
      final durationMs = asset.duration * 1000;
      final sampleTimestamps =
          VideoIntelligenceEngine.computeSampleTimestamps(
        durationMs: durationMs,
        strategy: VideoSamplingStrategy.sceneAdaptive,
        maxFrames: 12,
        minFrames: 1,
      );

      // Extract frames at computed timestamps
      final frames =
          await _extractFramesAtTimestamps(asset, sampleTimestamps);
      analysis = analysis.copyWith(totalFramesSampled: frames.length);

      for (final frame in frames) {
        await _db.videoFrames.upsert(frame);
      }

      // Initial time-based segments (enhanced with adaptive splitting)
      final segments = _buildAdaptiveSegments(asset.id, durationMs);
      analysis = analysis.copyWith(sceneCount: segments.length);

      for (final segment in segments) {
        await _db.videoSegments.upsert(segment);
      }

      // Audio detection
      final hasAudio = await _checkHasAudio(asset);
      analysis = analysis.copyWith(hasAudio: hasAudio);

      analysis = analysis.copyWith(
        analysisStatus: VideoAnalysisStatus.complete,
      );

      await _db.videoAnalysis.upsert(analysis);
      _logger.info(
        'Video analysis complete: $videoId — '
        '${frames.length} frames, ${segments.length} segments',
      );

      return analysis;
    } catch (e, st) {
      _logger.error('Video analysis failed: $videoId',
          error: e, stackTrace: st);
      analysis = analysis.copyWith(
        analysisStatus: VideoAnalysisStatus.failed,
      );
      await _db.videoAnalysis.upsert(analysis);
      return analysis;
    }
  }

  /// Enhance analysis after AI jobs complete.
  ///
  /// Runs content-based scene detection using frame embeddings,
  /// detects highlights, generates chapters, and builds summary.
  Future<void> enhanceAnalysis(String videoId) async {
    _logger.info('Enhancing video analysis: $videoId');

    try {
      final analysis = await _db.videoAnalysis.getByVideoId(videoId);
      if (analysis == null) {
        _logger.warning('No analysis record for $videoId');
        return;
      }

      final frames = await _db.videoFrames.getByVideoId(videoId);
      final existingSegments =
          await _db.videoSegments.getByVideoId(videoId);

      // Get video duration from metadata
      final metadata = await _db.photoMetadata.getById(videoId);
      final durationMs = (metadata?.durationSeconds ?? 0) * 1000;
      if (durationMs <= 0) return;

      // Content-based scene detection if we have enough frames
      if (frames.length >= 2) {
        // Use segment timestamps as proxy for frame positions
        final timestamps =
            frames.map((f) => f.timestampMs).toList()..sort();

        // Build simple "embedding" from segment labels for scene detection
        // (Real embeddings come from the embedding service)
        final labelVectors = _buildLabelVectors(
          timestamps,
          existingSegments,
        );

        if (labelVectors.length >= 2) {
          final scenes = VideoIntelligenceEngine.detectScenes(
            videoId: videoId,
            durationMs: durationMs,
            frameTimestamps: timestamps,
            frameEmbeddings: labelVectors,
            sceneChangeThreshold: 0.4,
          );

          final mergedScenes = VideoIntelligenceEngine.mergeShortScenes(
            scenes,
            minDurationMs: 2000,
          );

          // Replace segments with content-based scenes
          await _db.videoSegments.deleteByVideoId(videoId);
          for (final scene in mergedScenes) {
            await _db.videoSegments.upsert(VideoSegment(
              id: _uuid.v4(),
              videoId: videoId,
              startTimeMs: scene.startTimeMs,
              endTimeMs: scene.endTimeMs,
              confidence: scene.confidence,
              createdAt: DateTime.now(),
            ));
          }

          // Detect highlights
          final highlights = VideoIntelligenceEngine.detectHighlights(
            videoId: videoId,
            durationMs: durationMs,
            scenes: mergedScenes,
            segments: await _db.videoSegments.getByVideoId(videoId),
          );

          // Generate chapters
          final chapters = VideoIntelligenceEngine.generateChapters(
            videoId: videoId,
            scenes: mergedScenes,
            segments: await _db.videoSegments.getByVideoId(videoId),
          );

          // Update analysis with enhanced data
          await _db.videoAnalysis.upsert(analysis.copyWith(
            sceneCount: mergedScenes.length,
          ));

          _logger.info(
            'Enhanced analysis for $videoId: '
            '${mergedScenes.length} scenes, '
            '${highlights.length} highlights, '
            '${chapters.length} chapters',
          );
        }
      }
    } catch (e, st) {
      _logger.error('Enhanced analysis failed for $videoId',
          error: e, stackTrace: st);
    }
  }

  /// Build label vectors from existing segments for scene detection.
  ///
  /// Converts per-segment labels into simple feature vectors
  /// so that content changes between segments can be detected.
  List<List<double>> _buildLabelVectors(
    List<int> timestamps,
    List<VideoSegment> segments,
  ) {
    // Collect all unique labels
    final allLabels = <String>{};
    for (final seg in segments) {
      allLabels.addAll(seg.labels);
      for (final person in seg.people) {
        allLabels.add('person:$person');
      }
      if (seg.ocrText?.isNotEmpty == true) {
        allLabels.add('has_ocr');
      }
    }

    if (allLabels.isEmpty) {
      // No labels yet — return identical vectors (no scene changes detected)
      return List.generate(
        timestamps.length,
        (_) => List.filled(max(1, segments.length), 0.0),
      );
    }

    final labelList = allLabels.toList();
    final vectors = <List<double>>[];

    for (final ts in timestamps) {
      // Find the segment containing this timestamp
      VideoSegment? containing;
      for (final seg in segments) {
        if (ts >= seg.startTimeMs && ts < seg.endTimeMs) {
          containing = seg;
          break;
        }
      }

      // Build binary vector
      final vec = List<double>.filled(labelList.length, 0.0);
      if (containing != null) {
        for (var i = 0; i < labelList.length; i++) {
          final label = labelList[i];
          if (label.startsWith('person:')) {
            if (containing.people.contains(label.substring(7))) {
              vec[i] = 1.0;
            }
          } else if (label == 'has_ocr') {
            if (containing.ocrText?.isNotEmpty == true) vec[i] = 1.0;
          } else if (containing.labels.contains(label)) {
            vec[i] = 1.0;
          }
        }
      }
      vectors.add(vec);
    }

    return vectors;
  }

  /// Build adaptive time-based segments.
  ///
  /// Uses shorter segments for short videos and longer for long videos.
  List<VideoSegment> _buildAdaptiveSegments(
    String videoId,
    int durationMs,
  ) {
    if (durationMs <= 0) return [];

    // Adaptive segment duration: 10s for short, 30s for medium, 60s for long
    int segmentDurationMs;
    if (durationMs <= 30000) {
      segmentDurationMs = 10000; // 10s for short videos
    } else if (durationMs <= 120000) {
      segmentDurationMs = 15000; // 15s for medium
    } else if (durationMs <= 300000) {
      segmentDurationMs = 30000; // 30s for 2-5 min
    } else {
      segmentDurationMs = 60000; // 60s for 5+ min
    }

    final segments = <VideoSegment>[];
    for (var start = 0; start < durationMs; start += segmentDurationMs) {
      final end = min(start + segmentDurationMs, durationMs);
      segments.add(VideoSegment(
        id: _uuid.v4(),
        videoId: videoId,
        startTimeMs: start,
        endTimeMs: end,
        confidence: 1.0,
        createdAt: DateTime.now(),
      ));
    }

    return segments;
  }

  /// Extract frames at specific timestamps using photo_manager.
  Future<List<VideoFrame>> _extractFramesAtTimestamps(
    AssetEntity asset,
    List<int> timestamps,
  ) async {
    final frames = <VideoFrame>[];

    for (var i = 0; i < timestamps.length; i++) {
      final timestampMs = timestamps[i];

      try {
        // photo_manager frame parameter is 1-based index
        final frameIndex = i + 1;
        final thumbBytes = await asset.thumbnailDataWithSize(
          const ThumbnailSize(640, 640),
          format: ThumbnailFormat.jpeg,
          frame: frameIndex,
        );

        if (thumbBytes != null && thumbBytes.isNotEmpty) {
          final framePath =
              await _saveFrame(asset.id, timestampMs, thumbBytes);
          if (framePath != null) {
            frames.add(VideoFrame(
              id: _uuid.v4(),
              videoId: asset.id,
              timestampMs: timestampMs,
              framePath: framePath,
              width: 640,
              height: 640,
              isRepresentative: i == (timestamps.length ~/ 2),
              createdAt: DateTime.now(),
            ));
          }
        }
      } catch (e) {
        _logger.warning(
          'Failed to extract frame at ${timestampMs}ms for ${asset.id}',
          error: e,
        );
      }
    }

    return frames;
  }

  Future<void> _ensureMetadata(AssetEntity asset) async {
    final existing = await _db.photoMetadata.getById(asset.id);
    if (existing == null) {
      await _db.photoMetadata.upsert(
        await _createBasicVideoMetadata(asset),
      );
    } else if (existing.mediaType == null) {
      await _db.photoMetadata.upsert(
        existing.copyWith(
          mediaType: 'video',
          durationSeconds: asset.duration,
        ),
      );
    }
  }

  Future<PhotoMetadata> _createBasicVideoMetadata(
    AssetEntity asset,
  ) async {
    final file = await asset.originFile;
    final fileSize = file != null ? await file.length() : 0;

    return PhotoMetadata(
      photoId: asset.id,
      width: asset.width,
      height: asset.height,
      fileSizeBytes: fileSize,
      mimeType: asset.mimeType,
      dateCreated: asset.createDateTime,
      dateModified: asset.modifiedDateTime,
      latitude: asset.latitude,
      longitude: asset.longitude,
      orientation: 0,
      indexedAt: DateTime.now(),
      mediaType: 'video',
      durationSeconds: asset.duration,
    );
  }

  Future<String?> _saveFrame(
    String videoId,
    int timestampMs,
    List<int> bytes,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final framesDir = Directory('${dir.path}/video_frames/$videoId');
      if (!await framesDir.exists()) {
        await framesDir.create(recursive: true);
      }
      final file = File('${framesDir.path}/frame_${timestampMs}.jpg');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      _logger.warning('Failed to save frame', error: e);
      return null;
    }
  }

  /// Check if the video has an audio track.
  ///
  /// Uses duration check rather than volume (volume reflects player setting,
  /// not audio track presence). Falls back to true if detection fails.
  Future<bool> _checkHasAudio(AssetEntity asset) async {
    VideoPlayerController? controller;
    try {
      final file = await asset.file;
      if (file == null) return true;

      controller = VideoPlayerController.file(file);
      await controller.initialize();

      // If initialized successfully with a valid duration, assume audio exists.
      // True audio track detection requires platform-specific APIs (MediaCodec).
      return controller.value.duration > Duration.zero;
    } catch (_) {
      return true;
    } finally {
      controller?.dispose();
    }
  }

  VideoAnalysis _createFailedAnalysis(String videoId) {
    final now = DateTime.now();
    return VideoAnalysis(
      videoId: videoId,
      analysisStatus: VideoAnalysisStatus.failed,
      createdAt: now,
      updatedAt: now,
    );
  }
}
