import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../core/logging/app_logger.dart';
import '../../../domain/models/video_segment.dart';

const _uuid = Uuid();

/// A video scene (temporal segment with semantic content).
///
/// Scenes represent coherent temporal chunks identified by content
/// changes (visual similarity shifts, not just time-based splits).
class VideoScene {
  final String id;
  final String videoId;
  final int startTimeMs;
  final int endTimeMs;
  final String? label;
  final double confidence;
  final String? representativeFramePath;
  final List<String> tags;
  final DateTime createdAt;

  const VideoScene({
    required this.id,
    required this.videoId,
    required this.startTimeMs,
    required this.endTimeMs,
    this.label,
    this.confidence = 1.0,
    this.representativeFramePath,
    this.tags = const [],
    required this.createdAt,
  });

  int get durationMs => endTimeMs - startTimeMs;
  double get startTimeSeconds => startTimeMs / 1000.0;
  double get endTimeSeconds => endTimeMs / 1000.0;

  String get startTimeFormatted => _formatMs(startTimeMs);
  String get endTimeFormatted => _formatMs(endTimeMs);

  static String _formatMs(int ms) {
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    final millis = (ms % 1000) ~/ 100;
    return '${min.toString().padLeft(2, '0')}:'
        '${sec.toString().padLeft(2, '0')}'
        '.$millis';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'video_id': videoId,
        'start_time_ms': startTimeMs,
        'end_time_ms': endTimeMs,
        'label': label,
        'confidence': confidence,
        'representative_frame_path': representativeFramePath,
        'tags': tags,
        'created_at': createdAt.toIso8601String(),
      };

  factory VideoScene.fromMap(Map<String, dynamic> map) => VideoScene(
        id: map['id'] as String,
        videoId: map['video_id'] as String,
        startTimeMs: map['start_time_ms'] as int,
        endTimeMs: map['end_time_ms'] as int,
        label: map['label'] as String?,
        confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
        representativeFramePath: map['representative_frame_path'] as String?,
        tags: List<String>.from(map['tags'] as List? ?? []),
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

/// A highlight candidate — a moment deemed noteworthy by the engine.
class VideoHighlight {
  final String id;
  final String videoId;
  final int startTimeMs;
  final int endTimeMs;
  final double score;
  final String reason;
  final List<String> evidence;
  final DateTime createdAt;

  const VideoHighlight({
    required this.id,
    required this.videoId,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.score,
    required this.reason,
    this.evidence = const [],
    required this.createdAt,
  });

  int get durationMs => endTimeMs - startTimeMs;

  Map<String, dynamic> toMap() => {
        'id': id,
        'video_id': videoId,
        'start_time_ms': startTimeMs,
        'end_time_ms': endTimeMs,
        'score': score,
        'reason': reason,
        'evidence': evidence,
        'created_at': createdAt.toIso8601String(),
      };

  factory VideoHighlight.fromMap(Map<String, dynamic> map) => VideoHighlight(
        id: map['id'] as String,
        videoId: map['video_id'] as String,
        startTimeMs: map['start_time_ms'] as int,
        endTimeMs: map['end_time_ms'] as int,
        score: (map['score'] as num).toDouble(),
        reason: map['reason'] as String,
        evidence: List<String>.from(map['evidence'] as List? ?? []),
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

/// A video chapter — a named section for navigation.
class VideoChapter {
  final String id;
  final String videoId;
  final int startTimeMs;
  final int endTimeMs;
  final String title;
  final int index;

  const VideoChapter({
    required this.id,
    required this.videoId,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.title,
    required this.index,
  });

  String get timeLabel => VideoScene._formatMs(startTimeMs);

  Map<String, dynamic> toMap() => {
        'id': id,
        'video_id': videoId,
        'start_time_ms': startTimeMs,
        'end_time_ms': endTimeMs,
        'title': title,
        'index': index,
      };

  factory VideoChapter.fromMap(Map<String, dynamic> map) => VideoChapter(
        id: map['id'] as String,
        videoId: map['video_id'] as String,
        startTimeMs: map['start_time_ms'] as int,
        endTimeMs: map['end_time_ms'] as int,
        title: map['title'] as String,
        index: map['index'] as int,
      );
}

/// Unified video intelligence engine.
///
/// Coordinates all video analysis: frame sampling, scene detection,
/// content analysis (faces, objects, OCR), embedding generation,
/// highlight detection, chapter generation, and search.
///
/// Integrates with existing infrastructure:
/// - AI providers (BlazeFace, YOLO, OCR) via frame extraction
/// - Embedding service via representative frames
/// - Knowledge Graph via entity/relationship creation
/// - Search service via video segment queries
/// - Memory/Event systems via temporal clustering
class VideoIntelligenceEngine {
  VideoIntelligenceEngine({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  // =========================================================================
  // TEMPORAL FRAME SAMPLING (Step 4)
  // =========================================================================

  /// Sample timestamps for a video based on duration and strategy.
  ///
  /// Returns list of timestamps in milliseconds to extract frames at.
  /// Does NOT download or process any frames — just computes timestamps.
  static List<int> computeSampleTimestamps({
    required int durationMs,
    required VideoSamplingStrategy strategy,
    int maxFrames = 12,
    int minFrames = 1,
  }) {
    if (durationMs <= 0) return [];

    final effectiveMax = max(minFrames, min(maxFrames, durationMs ~/ 1000));

    switch (strategy) {
      case VideoSamplingStrategy.fixedInterval:
        return _fixedIntervalSampling(durationMs, effectiveMax);

      case VideoSamplingStrategy.sceneAdaptive:
        return _adaptiveSampling(durationMs, effectiveMax);

      case VideoSamplingStrategy.keyMoments:
        return _keyMomentsSampling(durationMs, effectiveMax);
    }
  }

  static List<int> _fixedIntervalSampling(int durationMs, int maxFrames) {
    if (maxFrames <= 1) return [durationMs ~/ 2];
    final interval = durationMs ~/ maxFrames;
    return List.generate(maxFrames, (i) => i * interval + interval ~/ 2);
  }

  static List<int> _adaptiveSampling(int durationMs, int maxFrames) {
    // Dense at start (intro) and middle, sparse at end
    final timestamps = <int>[];
    final quarter = durationMs ~/ 4;

    // First 25%: dense sampling (30% of frames)
    final earlyCount = max(1, (maxFrames * 0.3).round());
    for (var i = 0; i < earlyCount; i++) {
      timestamps.add((quarter * i ~/ earlyCount) + 500);
    }

    // Middle 50%: even sampling (50% of frames)
    final midCount = max(1, (maxFrames * 0.5).round());
    for (var i = 0; i < midCount; i++) {
      timestamps.add(quarter + (quarter * 2 * i ~/ midCount) + 500);
    }

    // Last 25%: sparse (20% of frames)
    final endCount = max(1, maxFrames - timestamps.length);
    for (var i = 0; i < endCount; i++) {
      timestamps.add(
        quarter * 3 + (quarter * i ~/ max(endCount, 1)) + 500,
      );
    }

    timestamps.sort();
    return timestamps.take(maxFrames).toList();
  }

  static List<int> _keyMomentsSampling(int durationMs, int maxFrames) {
    // Focus on common "interesting" moments: first 5s, 25%, 50%, 75%, last 5s
    final timestamps = <int>[
      2500, // 0:02.5 — opening shot
      (durationMs * 0.25).toInt(),
      (durationMs * 0.50).toInt(),
      (durationMs * 0.75).toInt(),
      max(0, durationMs - 5000), // last 5 seconds
    ];

    // Fill remaining slots with even distribution
    while (timestamps.length < maxFrames) {
      final step = durationMs ~/ (timestamps.length + 1);
      final newTimestamps = <int>[];
      for (var i = 1; i <= timestamps.length + 1; i++) {
        newTimestamps.add(i * step);
      }
      timestamps.addAll(newTimestamps);
      timestamps.sort();
      final deduped = <int>{};
      for (final t in timestamps) {
        deduped.add(t);
      }
      timestamps
        ..clear()
        ..addAll(deduped);
      if (timestamps.length >= maxFrames) break;
      // Safety: prevent infinite loop
      if (timestamps.length >= durationMs ~/ 1000) break;
    }

    return timestamps.take(maxFrames).toList();
  }

  // =========================================================================
  // SCENE DETECTION (Step 6) — content-based
  // =========================================================================

  /// Detect scene boundaries from a list of frame timestamps and their
  /// feature vectors (embedding differences between consecutive frames).
  ///
  /// Uses a threshold on embedding cosine distance to identify scene changes.
  /// Returns ordered list of VideoScene.
  static List<VideoScene> detectScenes({
    required String videoId,
    required int durationMs,
    required List<int> frameTimestamps,
    required List<List<double>> frameEmbeddings,
    double sceneChangeThreshold = 0.3,
  }) {
    if (frameTimestamps.length < 2 || frameEmbeddings.length < 2) {
      // Can't detect scenes with less than 2 frames
      if (frameTimestamps.isNotEmpty) {
        return [
          VideoScene(
            id: _uuid.v4(),
            videoId: videoId,
            startTimeMs: 0,
            endTimeMs: durationMs,
            label: 'Full video',
            confidence: 0.5,
            createdAt: DateTime.now(),
          ),
        ];
      }
      return [];
    }

    final sceneBoundaries = <int>[0]; // Start with 0ms

    // Compare consecutive frame embeddings
    for (var i = 1; i < frameEmbeddings.length; i++) {
      final distance = _cosineDistance(
        frameEmbeddings[i - 1],
        frameEmbeddings[i],
      );
      if (distance > sceneChangeThreshold) {
        sceneBoundaries.add(frameTimestamps[i]);
      }
    }

    sceneBoundaries.add(durationMs); // End boundary

    // Build scenes from boundaries
    final scenes = <VideoScene>[];
    for (var i = 0; i < sceneBoundaries.length - 1; i++) {
      final start = sceneBoundaries[i];
      final end = sceneBoundaries[i + 1];
      if (end - start < 1000) continue; // Skip sub-second scenes

      scenes.add(VideoScene(
        id: _uuid.v4(),
        videoId: videoId,
        startTimeMs: start,
        endTimeMs: end,
        confidence: 0.7,
        createdAt: DateTime.now(),
      ));
    }

    return scenes;
  }

  /// Merge short scenes into neighbors.
  static List<VideoScene> mergeShortScenes(
    List<VideoScene> scenes, {
    int minDurationMs = 3000,
  }) {
    if (scenes.isEmpty) return scenes;

    final merged = <VideoScene>[scenes.first];
    for (var i = 1; i < scenes.length; i++) {
      final prev = merged.last;
      final current = scenes[i];
      if (current.durationMs < minDurationMs) {
        // Merge into previous
        merged[merged.length - 1] = VideoScene(
          id: prev.id,
          videoId: prev.videoId,
          startTimeMs: prev.startTimeMs,
          endTimeMs: current.endTimeMs,
          label: prev.label ?? current.label,
          confidence: max(prev.confidence, current.confidence),
          representativeFramePath:
              prev.representativeFramePath ?? current.representativeFramePath,
          tags: [...prev.tags, ...current.tags],
          createdAt: prev.createdAt,
        );
      } else {
        merged.add(current);
      }
    }

    return merged;
  }

  // =========================================================================
  // HIGHLIGHT DETECTION (Step 22-23)
  // =========================================================================

  /// Detect highlight candidates from video analysis data.
  ///
  /// Uses multiple signals: segment density, people presence, object variety,
  /// OCR events, and visual uniqueness to score each temporal region.
  static List<VideoHighlight> detectHighlights({
    required String videoId,
    required int durationMs,
    required List<VideoScene> scenes,
    required List<VideoSegment> segments,
  }) {
    final highlights = <VideoHighlight>[];

    for (final scene in scenes) {
      final score = _scoreHighlight(scene, segments, durationMs);
      if (score >= 0.4) {
        final reasons = _explainHighlight(scene, segments);
        highlights.add(VideoHighlight(
          id: _uuid.v4(),
          videoId: videoId,
          startTimeMs: scene.startTimeMs,
          endTimeMs: scene.endTimeMs,
          score: score,
          reason: reasons.join('; '),
          evidence: reasons,
          createdAt: DateTime.now(),
        ));
      }
    }

    // Sort by score descending
    highlights.sort((a, b) => b.score.compareTo(a.score));
    return highlights;
  }

  static double _scoreHighlight(
    VideoScene scene,
    List<VideoSegment> segments,
    int totalDuration,
  ) {
    var score = 0.0;

    // Find overlapping segments
    final overlapping = segments.where((s) =>
        s.startTimeMs < scene.endTimeMs && s.endTimeMs > scene.startTimeMs);

    // People presence (high signal)
    final peopleCount = overlapping
        .where((s) => s.people.isNotEmpty)
        .length;
    score += min(0.3, peopleCount * 0.1);

    // Object variety (medium signal)
    final objectLabels = <String>{};
    for (final s in overlapping) {
      objectLabels.addAll(s.labels);
    }
    score += min(0.2, objectLabels.length * 0.04);

    // OCR events (medium signal)
    final hasOcr = overlapping.any((s) => s.ocrText?.isNotEmpty == true);
    if (hasOcr) score += 0.1;

    // Scene duration relative to average (shorter = more focused = interesting)
    final avgSceneDuration = totalDuration / max(1, segments.length);
    if (scene.durationMs < avgSceneDuration * 0.7) {
      score += 0.1;
    }

    // Visual uniqueness (if scene has confidence from embedding distance)
    score += scene.confidence * 0.1;

    return score.clamp(0.0, 1.0);
  }

  static List<String> _explainHighlight(
    VideoScene scene,
    List<VideoSegment> segments,
  ) {
    final reasons = <String>[];
    final overlapping = segments.where((s) =>
        s.startTimeMs < scene.endTimeMs && s.endTimeMs > scene.startTimeMs);

    final peopleCount = overlapping
        .where((s) => s.people.isNotEmpty)
        .length;
    if (peopleCount > 0) {
      reasons.add('$peopleCount people detected');
    }

    final objectLabels = <String>{};
    for (final s in overlapping) {
      objectLabels.addAll(s.labels);
    }
    if (objectLabels.isNotEmpty) {
      reasons.add('Objects: ${objectLabels.take(3).join(', ')}');
    }

    if (overlapping.any((s) => s.ocrText?.isNotEmpty == true)) {
      reasons.add('Text detected on screen');
    }

    return reasons.isEmpty ? ['Visual content'] : reasons;
  }

  // =========================================================================
  // CHAPTER GENERATION (Step 21)
  // =========================================================================

  /// Generate chapters from scenes and highlights.
  ///
  /// Chapters are derived from scene boundaries with labels
  /// based on the most prominent content in each scene.
  static List<VideoChapter> generateChapters({
    required String videoId,
    required List<VideoScene> scenes,
    required List<VideoSegment> segments,
  }) {
    final chapters = <VideoChapter>[];

    for (var i = 0; i < scenes.length; i++) {
      final scene = scenes[i];
      final title = _generateChapterTitle(scene, segments);

      chapters.add(VideoChapter(
        id: _uuid.v4(),
        videoId: videoId,
        startTimeMs: scene.startTimeMs,
        endTimeMs: scene.endTimeMs,
        title: title,
        index: i,
      ));
    }

    return chapters;
  }

  static String _generateChapterTitle(
    VideoScene scene,
    List<VideoSegment> segments,
  ) {
    // Use scene label if available
    if (scene.label != null && scene.label!.isNotEmpty) {
      return scene.label!;
    }

    // Aggregate content from overlapping segments
    final overlapping = segments.where((s) =>
        s.startTimeMs < scene.endTimeMs && s.endTimeMs > scene.startTimeMs);

    final labels = <String>{};
    for (final s in overlapping) {
      if (s.people.isNotEmpty) labels.add('People');
      labels.addAll(s.labels.take(2));
    }

    if (labels.isEmpty) {
      return 'Scene ${scene.startTimeFormatted}';
    }

    return labels.take(2).join(' & ');
  }

  // =========================================================================
  // VIDEO SUMMARY (Step 41)
  // =========================================================================

  /// Generate a structured summary from video analysis data.
  ///
  /// Uses only factual extracted information — no fabrication.
  static VideoSummary generateSummary({
    required String videoId,
    required int durationMs,
    required List<VideoScene> scenes,
    required List<VideoSegment> segments,
    required List<VideoHighlight> highlights,
    bool hasAudio = false,
    String transcriptionStatus = 'none',
  }) {
    // Aggregate people
    final people = <String>{};
    for (final s in segments) {
      people.addAll(s.people);
    }

    // Aggregate objects
    final objects = <String>{};
    for (final s in segments) {
      objects.addAll(s.labels);
    }

    // Aggregate OCR text
    final ocrTexts = <String>{};
    for (final s in segments) {
      if (s.ocrText?.isNotEmpty == true) ocrTexts.add(s.ocrText!);
    }

    return VideoSummary(
      videoId: videoId,
      durationMs: durationMs,
      sceneCount: scenes.length,
      peopleCount: people.length,
      people: people.toList(),
      objectLabels: objects.toList(),
      ocrTexts: ocrTexts.toList(),
      highlightCount: highlights.length,
      hasAudio: hasAudio,
      transcriptionStatus: transcriptionStatus,
    );
  }

  // =========================================================================
  // SEARCH HELPERS (Steps 17-19)
  // =========================================================================

  /// Search video segments by a combination of signals.
  static List<VideoSearchHit> searchVideo({
    required List<VideoSegment> segments,
    String? query,
    String? personId,
    String? objectLabel,
    int? startTimeMs,
    int? endTimeMs,
    double minConfidence = 0.0,
  }) {
    final hits = <VideoSearchHit>[];

    for (final seg in segments) {
      if ((seg.confidence ?? 0) < minConfidence) continue;
      if (startTimeMs != null && seg.endTimeMs < startTimeMs) continue;
      if (endTimeMs != null && seg.startTimeMs > endTimeMs) continue;

      var score = 0.0;
      final reasons = <String>[];

      // Time range match — base score for being in range
      if (startTimeMs != null || endTimeMs != null) {
        score += 0.1;
        reasons.add('In time range');
      }

      // Text query match
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        if (seg.ocrText?.toLowerCase().contains(q) == true) {
          score += 0.4;
          reasons.add('OCR: "${seg.ocrText}"');
        }
        if (seg.labels.any((l) => l.toLowerCase().contains(q))) {
          score += 0.3;
          reasons.add('Object: ${seg.labels.firstWhere((l) => l.toLowerCase().contains(q))}');
        }
      }

      // Person match
      if (personId != null && seg.people.contains(personId)) {
        score += 0.5;
        reasons.add('Person detected');
      }

      // Object match
      if (objectLabel != null &&
          seg.labels.any((l) => l.toLowerCase() == objectLabel.toLowerCase())) {
        score += 0.4;
        reasons.add('Object: $objectLabel');
      }

      if (score > 0) {
        hits.add(VideoSearchHit(
          segment: seg,
          score: score,
          reasons: reasons,
        ));
      }
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  // =========================================================================
  // UTILITIES
  // =========================================================================

  /// Cosine distance between two vectors (1 - cosine similarity).
  static double _cosineDistance(List<double> a, List<double> b) {
    if (a.length != b.length) return 1.0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    if (denom == 0) return 1.0;
    return (1.0 - dot / denom).clamp(0.0, 1.0);
  }
}

/// Frame sampling strategy.
enum VideoSamplingStrategy {
  /// Evenly spaced frames across the video.
  fixedInterval,

  /// Denser at start/middle, sparse at end.
  sceneAdaptive,

  /// Focus on common "interesting" moments.
  keyMoments,
}

/// A search hit within a video.
class VideoSearchHit {
  final VideoSegment segment;
  final double score;
  final List<String> reasons;

  const VideoSearchHit({
    required this.segment,
    required this.score,
    required this.reasons,
  });
}

/// Structured video summary.
class VideoSummary {
  final String videoId;
  final int durationMs;
  final int sceneCount;
  final int peopleCount;
  final List<String> people;
  final List<String> objectLabels;
  final List<String> ocrTexts;
  final int highlightCount;
  final bool hasAudio;
  final String transcriptionStatus;

  const VideoSummary({
    required this.videoId,
    required this.durationMs,
    required this.sceneCount,
    required this.peopleCount,
    required this.people,
    required this.objectLabels,
    required this.ocrTexts,
    required this.highlightCount,
    required this.hasAudio,
    required this.transcriptionStatus,
  });

  String get durationFormatted {
    final totalSec = durationMs ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() => {
        'video_id': videoId,
        'duration_ms': durationMs,
        'duration': durationFormatted,
        'scene_count': sceneCount,
        'people_count': peopleCount,
        'people': people,
        'object_labels': objectLabels,
        'ocr_texts': ocrTexts,
        'highlight_count': highlightCount,
        'has_audio': hasAudio,
        'transcription_status': transcriptionStatus,
      };
}
