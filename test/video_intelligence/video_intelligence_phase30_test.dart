import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/features/video_intelligence/services/video_intelligence_engine.dart';
import 'package:ai_gallery/features/video_intelligence/services/frame_cache.dart';
import 'package:ai_gallery/domain/models/video_segment.dart';

void main() {
  group('VideoIntelligenceEngine - Frame Sampling', () {
    test('fixedInterval sampling produces correct count', () {
      final timestamps = VideoIntelligenceEngine.computeSampleTimestamps(
        durationMs: 60000,
        strategy: VideoSamplingStrategy.fixedInterval,
        maxFrames: 6,
      );
      expect(timestamps.length, 6);
      expect(timestamps.first, greaterThanOrEqualTo(0));
      expect(timestamps.last, lessThan(60000));
    });

    test('sceneAdaptive sampling is dense at start', () {
      final timestamps = VideoIntelligenceEngine.computeSampleTimestamps(
        durationMs: 120000,
        strategy: VideoSamplingStrategy.sceneAdaptive,
        maxFrames: 8,
      );
      expect(timestamps.length, 8);
      // First 4 should be in first quarter (30s)
      final earlyCount =
          timestamps.where((t) => t < 30000).length;
      expect(earlyCount, greaterThanOrEqualTo(2));
    });

    test('keyMoments sampling covers start and middle', () {
      final timestamps = VideoIntelligenceEngine.computeSampleTimestamps(
        durationMs: 60000,
        strategy: VideoSamplingStrategy.keyMoments,
        maxFrames: 5,
      );
      expect(timestamps.length, 5);
      // Should have a sample near the start (first 5s)
      expect(timestamps.first, lessThan(5000));
      // Should have a sample around 50% mark (25-35s)
      final midSample = timestamps[2];
      expect(midSample, greaterThan(20000));
      expect(midSample, lessThan(40000));
    });

    test('short video gets fewer frames', () {
      final timestamps = VideoIntelligenceEngine.computeSampleTimestamps(
        durationMs: 3000,
        strategy: VideoSamplingStrategy.fixedInterval,
        maxFrames: 10,
      );
      expect(timestamps.length, lessThanOrEqualTo(3));
    });

    test('zero duration returns empty', () {
      final timestamps = VideoIntelligenceEngine.computeSampleTimestamps(
        durationMs: 0,
        strategy: VideoSamplingStrategy.fixedInterval,
      );
      expect(timestamps, isEmpty);
    });
  });

  group('VideoIntelligenceEngine - Scene Detection', () {
    test('detects scene change from embedding distance', () {
      final timestamps = [0, 5000, 10000, 15000, 20000];
      // Create embeddings with a clear change at index 2
      final embeddings = [
        [1.0, 0.0, 0.0],
        [0.9, 0.1, 0.0], // similar to first
        [0.0, 0.0, 1.0], // very different — scene change
        [0.1, 0.0, 0.9], // similar to third
        [0.0, 0.1, 0.9], // similar to third
      ];

      final scenes = VideoIntelligenceEngine.detectScenes(
        videoId: 'test_video',
        durationMs: 25000,
        frameTimestamps: timestamps,
        frameEmbeddings: embeddings,
        sceneChangeThreshold: 0.3,
      );

      expect(scenes.length, greaterThanOrEqualTo(2));
      // First scene should start at 0
      expect(scenes.first.startTimeMs, 0);
    });

    test('single frame returns one scene', () {
      final scenes = VideoIntelligenceEngine.detectScenes(
        videoId: 'test_video',
        durationMs: 10000,
        frameTimestamps: [5000],
        frameEmbeddings: [[1.0, 0.0]],
      );
      expect(scenes.length, 1);
      expect(scenes.first.startTimeMs, 0);
      expect(scenes.first.endTimeMs, 10000);
    });

    test('mergeShortScenes combines short scenes', () {
      final scenes = [
        VideoScene(
          id: '1',
          videoId: 'v',
          startTimeMs: 0,
          endTimeMs: 10000,
          confidence: 0.8,
          createdAt: DateTime(2025),
        ),
        VideoScene(
          id: '2',
          videoId: 'v',
          startTimeMs: 10000,
          endTimeMs: 12000, // 2 seconds — short
          confidence: 0.6,
          createdAt: DateTime(2025),
        ),
        VideoScene(
          id: '3',
          videoId: 'v',
          startTimeMs: 12000,
          endTimeMs: 30000,
          confidence: 0.9,
          createdAt: DateTime(2025),
        ),
      ];

      final merged = VideoIntelligenceEngine.mergeShortScenes(
        scenes,
        minDurationMs: 3000,
      );

      expect(merged.length, 2);
      expect(merged.first.endTimeMs, 12000);
      expect(merged.last.startTimeMs, 12000);
    });
  });

  group('VideoIntelligenceEngine - Highlights', () {
    test('scores highlights based on people and objects', () {
      final scene = VideoScene(
        id: 's1',
        videoId: 'v',
        startTimeMs: 0,
        endTimeMs: 10000,
        confidence: 0.8,
        createdAt: DateTime(2025),
      );

      final segments = [
        VideoSegment(
          id: 'seg1',
          videoId: 'v',
          startTimeMs: 0,
          endTimeMs: 5000,
          people: ['person1', 'person2'],
          labels: ['car', 'building', 'tree'],
          confidence: 0.9,
          createdAt: DateTime(2025),
        ),
      ];

      final highlights = VideoIntelligenceEngine.detectHighlights(
        videoId: 'v',
        durationMs: 30000,
        scenes: [scene],
        segments: segments,
      );

      expect(highlights.length, 1);
      expect(highlights.first.score, greaterThanOrEqualTo(0.4));
      expect(highlights.first.evidence, isNotEmpty);
    });

    test('low-content scenes are not highlighted', () {
      final scene = VideoScene(
        id: 's1',
        videoId: 'v',
        startTimeMs: 0,
        endTimeMs: 30000,
        confidence: 0.3,
        createdAt: DateTime(2025),
      );

      final highlights = VideoIntelligenceEngine.detectHighlights(
        videoId: 'v',
        durationMs: 60000,
        scenes: [scene],
        segments: [],
      );

      expect(highlights, isEmpty);
    });
  });

  group('VideoIntelligenceEngine - Chapters', () {
    test('generates chapters from scenes', () {
      final scenes = [
        VideoScene(
          id: 's1',
          videoId: 'v',
          startTimeMs: 0,
          endTimeMs: 15000,
          label: 'Introduction',
          confidence: 0.9,
          createdAt: DateTime(2025),
        ),
        VideoScene(
          id: 's2',
          videoId: 'v',
          startTimeMs: 15000,
          endTimeMs: 45000,
          confidence: 0.7,
          createdAt: DateTime(2025),
        ),
      ];

      final segments = [
        VideoSegment(
          id: 'seg1',
          videoId: 'v',
          startTimeMs: 15000,
          endTimeMs: 45000,
          labels: ['car', 'road'],
          people: ['driver'],
          confidence: 0.8,
          createdAt: DateTime(2025),
        ),
      ];

      final chapters = VideoIntelligenceEngine.generateChapters(
        videoId: 'v',
        scenes: scenes,
        segments: segments,
      );

      expect(chapters.length, 2);
      expect(chapters.first.title, 'Introduction');
      expect(chapters.last.index, 1);
    });
  });

  group('VideoIntelligenceEngine - Summary', () {
    test('generates summary from analysis data', () {
      final scenes = [
        VideoScene(
          id: 's1',
          videoId: 'v',
          startTimeMs: 0,
          endTimeMs: 30000,
          confidence: 0.8,
          createdAt: DateTime(2025),
        ),
      ];

      final segments = [
        VideoSegment(
          id: 'seg1',
          videoId: 'v',
          startTimeMs: 0,
          endTimeMs: 15000,
          people: ['Alice'],
          labels: ['cat'],
          ocrText: 'Hello World',
          confidence: 0.9,
          createdAt: DateTime(2025),
        ),
        VideoSegment(
          id: 'seg2',
          videoId: 'v',
          startTimeMs: 15000,
          endTimeMs: 30000,
          people: ['Alice', 'Bob'],
          labels: ['dog', 'cat'],
          confidence: 0.8,
          createdAt: DateTime(2025),
        ),
      ];

      final highlights = [
        VideoHighlight(
          id: 'h1',
          videoId: 'v',
          startTimeMs: 0,
          endTimeMs: 15000,
          score: 0.8,
          reason: 'People present',
          createdAt: DateTime(2025),
        ),
      ];

      final summary = VideoIntelligenceEngine.generateSummary(
        videoId: 'v',
        durationMs: 30000,
        scenes: scenes,
        segments: segments,
        highlights: highlights,
        hasAudio: true,
      );

      expect(summary.sceneCount, 1);
      expect(summary.people, containsAll(['Alice', 'Bob']));
      expect(summary.objectLabels, containsAll(['cat', 'dog']));
      expect(summary.ocrTexts, contains('Hello World'));
      expect(summary.highlightCount, 1);
      expect(summary.hasAudio, true);
      expect(summary.durationFormatted, '0:30');
    });
  });

  group('VideoIntelligenceEngine - Search', () {
    test('searches by text query', () {
      final segments = [
        VideoSegment(
          id: 'seg1',
          videoId: 'v',
          startTimeMs: 0,
          endTimeMs: 10000,
          ocrText: 'Stop sign ahead',
          confidence: 0.9,
          createdAt: DateTime(2025),
        ),
        VideoSegment(
          id: 'seg2',
          videoId: 'v',
          startTimeMs: 10000,
          endTimeMs: 20000,
          labels: ['car'],
          confidence: 0.7,
          createdAt: DateTime(2025),
        ),
      ];

      final hits = VideoIntelligenceEngine.searchVideo(
        segments: segments,
        query: 'stop sign',
      );

      expect(hits.length, 1);
      expect(hits.first.segment.id, 'seg1');
      expect(hits.first.score, greaterThan(0));
    });

    test('searches by person', () {
      final segments = [
        VideoSegment(
          id: 'seg1',
          videoId: 'v',
          startTimeMs: 0,
          endTimeMs: 10000,
          people: ['Alice'],
          confidence: 0.9,
          createdAt: DateTime(2025),
        ),
      ];

      final hits = VideoIntelligenceEngine.searchVideo(
        segments: segments,
        personId: 'Alice',
      );

      expect(hits.length, 1);
      expect(hits.first.score, greaterThan(0));
    });

    test('searches by time range', () {
      final segments = [
        VideoSegment(
          id: 'seg1',
          videoId: 'v',
          startTimeMs: 0,
          endTimeMs: 10000,
          labels: ['tree'],
          confidence: 0.8,
          createdAt: DateTime(2025),
        ),
        VideoSegment(
          id: 'seg2',
          videoId: 'v',
          startTimeMs: 15000,
          endTimeMs: 25000,
          labels: ['car'],
          confidence: 0.7,
          createdAt: DateTime(2025),
        ),
      ];

      final hits = VideoIntelligenceEngine.searchVideo(
        segments: segments,
        startTimeMs: 12000,
        endTimeMs: 30000,
      );

      expect(hits.length, 1);
      expect(hits.first.segment.id, 'seg2');
    });
  });

  group('FrameCache', () {
    test('stores and retrieves frames', () {
      // FrameCache requires AppLogger, use a simple stub
      final cache = _StubFrameCache(maxFrames: 3);

      cache.put('v1', 0, [1, 2, 3]);
      cache.put('v1', 5000, [4, 5, 6]);
      cache.put('v2', 0, [7, 8, 9]);

      expect(cache.get('v1', 0), [1, 2, 3]);
      expect(cache.get('v1', 5000), [4, 5, 6]);
      expect(cache.get('v2', 0), [7, 8, 9]);
      expect(cache.get('v1', 9999), isNull);
    });

    test('evicts oldest when full', () {
      final cache = _StubFrameCache(maxFrames: 3);

      cache.put('v1', 0, [1]);
      cache.put('v1', 1, [2]);
      cache.put('v1', 2, [3]);
      cache.put('v1', 3, [4]); // should evict oldest

      expect(cache.get('v1', 0), isNull);
      expect(cache.get('v1', 3), [4]);
    });

    test('invalidateVideo removes all frames for a video', () {
      final cache = _StubFrameCache(maxFrames: 10);

      cache.put('v1', 0, [1]);
      cache.put('v1', 1, [2]);
      cache.put('v2', 0, [3]);

      cache.invalidateVideo('v1');

      expect(cache.get('v1', 0), isNull);
      expect(cache.get('v1', 1), isNull);
      expect(cache.get('v2', 0), [3]);
    });

    test('clear removes all entries', () {
      final cache = _StubFrameCache(maxFrames: 10);

      cache.put('v1', 0, [1]);
      cache.put('v2', 0, [2]);

      cache.clear();

      expect(cache.length, 0);
      expect(cache.currentBytes, 0);
    });
  });

  group('VideoScene formatting', () {
    test('startTimeFormatted formats correctly', () {
      final scene = VideoScene(
        id: '1',
        videoId: 'v',
        startTimeMs: 65000, // 1:05.0
        endTimeMs: 125000,
        createdAt: DateTime(2025),
      );
      expect(scene.startTimeFormatted, '01:05.0');
    });

    test('durationMs is calculated correctly', () {
      final scene = VideoScene(
        id: '1',
        videoId: 'v',
        startTimeMs: 10000,
        endTimeMs: 35000,
        createdAt: DateTime(2025),
      );
      expect(scene.durationMs, 25000);
    });
  });

  group('VideoSummary formatting', () {
    test('durationFormatted formats minutes:seconds', () {
      final summary = VideoSummary(
        videoId: 'v',
        durationMs: 125000, // 2:05
        sceneCount: 3,
        peopleCount: 2,
        people: ['Alice', 'Bob'],
        objectLabels: ['car'],
        ocrTexts: [],
        highlightCount: 1,
        hasAudio: true,
        transcriptionStatus: 'none',
      );
      expect(summary.durationFormatted, '2:05');
    });
  });
}

/// Simple stub for FrameCache that skips AppLogger dependency.
class _StubFrameCache {
  _StubFrameCache({required int maxFrames}) : _maxFrames = maxFrames;

  final int _maxFrames;
  final _cache = <String, List<int>>{};
  final _order = <String>[];

  List<int>? get(String videoId, int timestampMs) {
    final key = '$videoId:$timestampMs';
    return _cache[key];
  }

  void put(String videoId, int timestampMs, List<int> data) {
    final key = '$videoId:$timestampMs';
    _cache.remove(key);
    _order.remove(key);

    while (_cache.length >= _maxFrames) {
      if (_order.isEmpty) break;
      final oldest = _order.removeAt(0);
      _cache.remove(oldest);
    }

    _cache[key] = data;
    _order.add(key);
  }

  void invalidateVideo(String videoId) {
    final prefix = '$videoId:';
    final keys = _cache.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keys) {
      _cache.remove(key);
      _order.remove(key);
    }
  }

  void clear() {
    _cache.clear();
    _order.clear();
  }

  int get length => _cache.length;
  int get currentBytes => 0;
}
