import 'dart:math';

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/video_frame.dart';

/// Analyzes video quality using existing frame data.
///
/// Uses blur scores, quality scores, and frame distribution
/// to compute an overall quality rating. No external models needed.
class VideoQualityService {
  VideoQualityService({
    required AppDatabase database,
    required AppLogger logger,
  })  : _db = database,
        _logger = logger;

  final AppDatabase _db;
  final AppLogger _logger;

  /// Analyze video quality and return a quality report.
  Future<VideoQualityReport> analyzeQuality(String videoId) async {
    final frames = await _db.videoFrames.getByVideoId(videoId);

    if (frames.isEmpty) {
      return VideoQualityReport(
        videoId: videoId,
        overallScore: 0,
        blurScore: 0,
        sharpnessScore: 0,
        exposureScore: 0,
        noiseScore: 0,
        frameCount: 0,
        issues: ['No frames sampled'],
      );
    }

    // Blur analysis
    final blurScores = frames
        .where((f) => f.blurScore != null)
        .map((f) => f.blurScore!)
        .toList();
    final avgBlur = blurScores.isNotEmpty
        ? blurScores.reduce((a, b) => a + b) / blurScores.length
        : 0.5;

    // Quality analysis
    final qualityScores = frames
        .where((f) => f.qualityScore != null)
        .map((f) => f.qualityScore!)
        .toList();
    final avgQuality = qualityScores.isNotEmpty
        ? qualityScores.reduce((a, b) => a + b) / qualityScores.length
        : 0.5;

    // Frame distribution (are frames spread evenly or clustered?)
    final distribution = _analyzeFrameDistribution(frames);

    // Detect issues
    final issues = <String>[];
    if (avgBlur > 0.7) issues.add('Most frames are blurry');
    if (avgQuality < 0.3) issues.add('Low overall quality');
    if (frames.length < 3) issues.add('Too few frames sampled');
    if (distribution < 0.3) issues.add('Frames poorly distributed');

    // Compute overall score (weighted average)
    final sharpnessScore = (1.0 - avgBlur).clamp(0.0, 1.0);
    final overall = (sharpnessScore * 0.4 +
            avgQuality * 0.4 +
            distribution * 0.2)
        .clamp(0.0, 1.0);

    return VideoQualityReport(
      videoId: videoId,
      overallScore: overall,
      blurScore: avgBlur,
      sharpnessScore: sharpnessScore,
      exposureScore: avgQuality, // proxy
      noiseScore: avgBlur * 0.8, // proxy
      frameCount: frames.length,
      issues: issues,
    );
  }

  /// Analyze how evenly frames are distributed across the video.
  ///
  /// Returns 0.0 (all clustered) to 1.0 (perfectly even).
  double _analyzeFrameDistribution(List<VideoFrame> frames) {
    if (frames.length < 2) return 0.5;

    final timestamps = frames.map((f) => f.timestampMs).toList()..sort();
    final gaps = <int>[];
    for (var i = 1; i < timestamps.length; i++) {
      gaps.add(timestamps[i] - timestamps[i - 1]);
    }

    if (gaps.isEmpty) return 0.5;

    final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;
    if (avgGap == 0) return 0.5;

    // Coefficient of variation (lower = more even)
    final variance = gaps
        .map((g) => (g - avgGap) * (g - avgGap))
        .reduce((a, b) => a + b) /
        gaps.length;
    final cv = sqrt(variance) / avgGap;

    // Convert CV to 0-1 score (CV=0 → 1.0, CV=2 → 0.0)
    return (1.0 - cv / 2.0).clamp(0.0, 1.0);
  }
}

/// Quality report for a video.
class VideoQualityReport {
  final String videoId;
  final double overallScore;
  final double blurScore;
  final double sharpnessScore;
  final double exposureScore;
  final double noiseScore;
  final int frameCount;
  final List<String> issues;

  const VideoQualityReport({
    required this.videoId,
    required this.overallScore,
    required this.blurScore,
    required this.sharpnessScore,
    required this.exposureScore,
    required this.noiseScore,
    required this.frameCount,
    required this.issues,
  });

  String get qualityLabel {
    if (overallScore >= 0.8) return 'Excellent';
    if (overallScore >= 0.6) return 'Good';
    if (overallScore >= 0.4) return 'Fair';
    if (overallScore >= 0.2) return 'Poor';
    return 'Very Poor';
  }

  Map<String, dynamic> toMap() => {
        'video_id': videoId,
        'overall_score': overallScore,
        'quality_label': qualityLabel,
        'blur_score': blurScore,
        'sharpness_score': sharpnessScore,
        'exposure_score': exposureScore,
        'noise_score': noiseScore,
        'frame_count': frameCount,
        'issues': issues,
      };
}
