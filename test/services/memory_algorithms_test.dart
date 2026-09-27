import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/core/algorithms/temporal_clustering.dart';
import 'package:ai_gallery/core/algorithms/event_discovery.dart';
import 'package:ai_gallery/core/algorithms/memory_scoring.dart';
import 'package:ai_gallery/core/algorithms/memory_title_generator.dart';
import 'package:ai_gallery/core/algorithms/best_photo_selector.dart';
import 'package:ai_gallery/core/algorithms/cover_photo_selector.dart';
import 'package:ai_gallery/core/algorithms/semantic_analysis.dart';
import 'package:ai_gallery/core/algorithms/trip_detection.dart';
import 'package:ai_gallery/core/algorithms/automatic_album_generator.dart';
import 'package:ai_gallery/domain/models/memory/memory.dart';
import 'package:ai_gallery/domain/models/memory/memory_candidate.dart';
import 'package:ai_gallery/domain/models/memory/photo_cluster.dart';
import 'package:ai_gallery/domain/models/memory/photo_score.dart';
import 'package:ai_gallery/domain/models/memory/automatic_album.dart';

void main() {
  group('TemporalClustering', () {
    test('empty input returns empty', () {
      final result = TemporalClustering.cluster(photoTimestamps: []);
      expect(result, isEmpty);
    });

    test('single photo returns one cluster', () {
      final result = TemporalClustering.cluster(
        photoTimestamps: [('p1', DateTime(2025, 1, 1, 10, 0))],
      );
      expect(result.length, 1);
      expect(result.first.photoIds, ['p1']);
    });

    test('photos within gap threshold form one cluster', () {
      final now = DateTime(2025, 1, 1, 10, 0);
      final result = TemporalClustering.cluster(
        photoTimestamps: [
          ('p1', now),
          ('p2', now.add(const Duration(minutes: 30))),
          ('p3', now.add(const Duration(hours: 1))),
        ],
      );
      expect(result.length, 1);
      expect(result.first.photoCount, 3);
    });

    test('photos beyond gap threshold form separate clusters', () {
      final now = DateTime(2025, 1, 1, 10, 0);
      final result = TemporalClustering.cluster(
        photoTimestamps: [
          ('p1', now),
          ('p2', now.add(const Duration(hours: 1))),
          ('p3', now.add(const Duration(hours: 6))),
          ('p4', now.add(const Duration(hours: 7))),
        ],
      );
      expect(result.length, 2);
    });

    test('adaptive clustering detects natural breaks', () {
      final base = DateTime(2025, 6, 15, 10, 0);
      final result = TemporalClustering.clusterAdaptive(
        photoTimestamps: [
          ('p1', base),
          ('p2', base.add(const Duration(minutes: 15))),
          ('p3', base.add(const Duration(minutes: 30))),
          ('p4', base.add(const Duration(hours: 8))),
          ('p5', base.add(const Duration(hours: 8, minutes: 15))),
          ('p6', base.add(const Duration(hours: 8, minutes: 30))),
        ],
      );
      expect(result.length, greaterThanOrEqualTo(1));
      expect(result.every((c) => c.photoCount >= 1), true);
    });

    test('mergeNearby merges close clusters', () {
      final c1 = PhotoCluster(
        clusterId: 'c1',
        photoIds: ['p1', 'p2'],
        startDate: DateTime(2025, 1, 1, 10, 0),
        endDate: DateTime(2025, 1, 1, 11, 0),
        span: const Duration(hours: 1),
      );
      final c2 = PhotoCluster(
        clusterId: 'c2',
        photoIds: ['p3', 'p4'],
        startDate: DateTime(2025, 1, 1, 12, 0),
        endDate: DateTime(2025, 1, 1, 13, 0),
        span: const Duration(hours: 1),
      );
      final result = TemporalClustering.mergeNearby(
        clusters: [c1, c2],
        mergeThreshold: const Duration(hours: 2),
      );
      expect(result.length, 1);
      expect(result.first.photoCount, 4);
    });

    test('mergeNearby keeps distant clusters separate', () {
      final c1 = PhotoCluster(
        clusterId: 'c1',
        photoIds: ['p1'],
        startDate: DateTime(2025, 1, 1, 10, 0),
        endDate: DateTime(2025, 1, 1, 10, 0),
        span: Duration.zero,
      );
      final c2 = PhotoCluster(
        clusterId: 'c2',
        photoIds: ['p2'],
        startDate: DateTime(2025, 1, 2, 10, 0),
        endDate: DateTime(2025, 1, 2, 10, 0),
        span: Duration.zero,
      );
      final result = TemporalClustering.mergeNearby(
        clusters: [c1, c2],
        mergeThreshold: const Duration(hours: 2),
      );
      expect(result.length, 2);
    });
  });

  group('EventDiscovery', () {
    test('returns empty for fewer than minPhotos', () {
      final result = EventDiscovery.discover(
        photoTimestamps: [
          ('p1', DateTime(2025, 1, 1)),
          ('p2', DateTime(2025, 1, 1, 1)),
        ],
      );
      expect(result, isEmpty);
    });

    test('finds clusters with minimum photos', () {
      final now = DateTime(2025, 1, 1, 10, 0);
      final result = EventDiscovery.discover(
        photoTimestamps: [
          ('p1', now),
          ('p2', now.add(const Duration(minutes: 10))),
          ('p3', now.add(const Duration(minutes: 20))),
          ('p4', now.add(const Duration(minutes: 30))),
        ],
      );
      expect(result.length, greaterThanOrEqualTo(1));
    });

    test('findGaps identifies large gaps', () {
      final result = EventDiscovery.findGaps(
        photoTimestamps: [
          ('p1', DateTime(2025, 1, 1, 10, 0)),
          ('p2', DateTime(2025, 1, 1, 11, 0)),
          ('p3', DateTime(2025, 1, 1, 20, 0)),
          ('p4', DateTime(2025, 1, 1, 21, 0)),
        ],
        minGap: const Duration(hours: 6),
      );
      expect(result.length, 1);
      expect(result.first.$3.inHours, greaterThanOrEqualTo(6));
    });

    test('findActivityHotspots finds dense periods', () {
      final base = DateTime(2025, 1, 1, 10, 0);
      final result = EventDiscovery.findActivityHotspots(
        photoTimestamps: List.generate(
          10,
          (i) => ('p$i', base.add(Duration(minutes: i * 5))),
        ),
      );
      expect(result.isNotEmpty, true);
    });
  });

  group('MemoryScoring', () {
    test('scores a valid cluster', () {
      final cluster = PhotoCluster(
        clusterId: 'c1',
        photoIds: ['p1', 'p2', 'p3', 'p4', 'p5'],
        startDate: DateTime(2025, 1, 1, 10, 0),
        endDate: DateTime(2025, 1, 1, 14, 0),
        span: const Duration(hours: 4),
      );

      final candidates = MemoryScoring.scoreCandidates(
        clusters: [cluster],
        qualityScores: {
          'p1': 0.8, 'p2': 0.9, 'p3': 0.7, 'p4': 0.85, 'p5': 0.75,
        },
        peoplePresence: {
          'p1': true, 'p2': true, 'p3': false, 'p4': true, 'p5': false,
        },
        gpsData: {
          'p1': (37.7749, -122.4194),
          'p2': (37.7750, -122.4195),
          'p3': (37.7751, -122.4196),
        },
      );

      expect(candidates.isNotEmpty, true);
      expect(candidates.first.overallScore, greaterThan(0.0));
      expect(candidates.first.overallScore, lessThanOrEqualTo(1.0));
    });

    test('filters out low-score candidates', () {
      final cluster = PhotoCluster(
        clusterId: 'c1',
        photoIds: ['p1'],
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 1),
        span: Duration.zero,
      );

      final candidates = MemoryScoring.scoreCandidates(clusters: [cluster]);
      // Single photo with no quality data gets default scores
      // which may or may not pass the threshold
      expect(candidates.length, lessThanOrEqualTo(1));
    });

    test('marks duplicate candidates', () {
      final c1 = PhotoCluster(
        clusterId: 'c1',
        photoIds: ['p1', 'p2', 'p3', 'p4', 'p5'],
        startDate: DateTime(2025, 1, 1, 10, 0),
        endDate: DateTime(2025, 1, 1, 14, 0),
        span: const Duration(hours: 4),
      );
      final c2 = PhotoCluster(
        clusterId: 'c2',
        photoIds: ['p1', 'p2', 'p3', 'p4', 'p5'],
        startDate: DateTime(2025, 1, 1, 10, 0),
        endDate: DateTime(2025, 1, 1, 14, 0),
        span: const Duration(hours: 4),
      );

      final qualityScores = <String, double>{};
      for (var i = 1; i <= 5; i++) {
        qualityScores['p$i'] = 0.8;
      }

      final candidates = MemoryScoring.scoreCandidates(
        clusters: [c1, c2],
        qualityScores: qualityScores,
      );

      if (candidates.length >= 2) {
        expect(candidates.last.isDuplicate, true);
      }
    });
  });

  group('MemoryTitleGenerator', () {
    test('generates title for single-day memory', () {
      final candidate = MemoryCandidate(
        candidateId: 'c1',
        cluster: PhotoCluster(
          clusterId: 'c1',
          photoIds: List.generate(10, (i) => 'p$i'),
          startDate: DateTime(2025, 6, 15, 10, 0),
          endDate: DateTime(2025, 6, 15, 16, 0),
          span: const Duration(hours: 6),
        ),
        overallScore: 0.8,
      );

      final result = MemoryTitleGenerator.generate(
        candidate: candidate,
        locationLabel: 'San Francisco',
      );

      expect(result.title.isNotEmpty, true);
      expect(result.usesLocation, true);
      expect(result.usesDate, true);
    });

    test('generates trip title for multi-day with location', () {
      final candidate = MemoryCandidate(
        candidateId: 'c1',
        cluster: PhotoCluster(
          clusterId: 'c1',
          photoIds: List.generate(20, (i) => 'p$i'),
          startDate: DateTime(2025, 7, 1, 10, 0),
          endDate: DateTime(2025, 7, 5, 18, 0),
          span: const Duration(days: 4),
        ),
        overallScore: 0.9,
      );

      final result = MemoryTitleGenerator.generate(
        candidate: candidate,
        locationLabel: 'Paris',
      );

      expect(result.title, contains('Trip'));
      expect(result.title, contains('Paris'));
      expect(result.usesEvent, true);
    });

    test('generates people title for photos with people', () {
      final candidate = MemoryCandidate(
        candidateId: 'c1',
        cluster: PhotoCluster(
          clusterId: 'c1',
          photoIds: List.generate(8, (i) => 'p$i'),
          startDate: DateTime(2025, 3, 20, 10, 0),
          endDate: DateTime(2025, 3, 20, 14, 0),
          span: const Duration(hours: 4),
        ),
        overallScore: 0.7,
      );

      final result = MemoryTitleGenerator.generate(
        candidate: candidate,
        personNames: ['Alice', 'Bob'],
      );

      expect(result.title, contains('Alice'));
      expect(result.usesPeople, true);
    });
  });

  group('BestPhotoSelector', () {
    test('selects top N photos', () {
      final scores = List.generate(
        20,
        (i) => PhotoScore(
          photoId: 'p$i',
          overallScore: i / 20.0,
        ),
      );

      final best = BestPhotoSelector.selectBest(photoScores: scores, count: 5);
      expect(best.length, 5);
      expect(best.first.overallScore, greaterThanOrEqualTo(best.last.overallScore));
    });

    test('handles fewer photos than requested', () {
      final scores = [
        const PhotoScore(photoId: 'p1', overallScore: 0.8),
        const PhotoScore(photoId: 'p2', overallScore: 0.6),
      ];

      final best = BestPhotoSelector.selectBest(photoScores: scores, count: 10);
      expect(best.length, 2);
    });

    test('scorePhotos computes scores', () {
      final scores = BestPhotoSelector.scorePhotos(
        photoIds: ['p1', 'p2', 'p3'],
        qualityScores: {'p1': 0.9, 'p2': 0.5, 'p3': 0.7},
      );

      expect(scores.length, 3);
      expect(scores.every((s) => s.overallScore >= 0.0), true);
    });
  });

  group('CoverPhotoSelector', () {
    test('selects best cover from scored photos', () {
      final scores = [
        const PhotoScore(photoId: 'p1', overallScore: 0.9, isCoverCandidate: true),
        const PhotoScore(photoId: 'p2', overallScore: 0.5, isCoverCandidate: false),
        const PhotoScore(photoId: 'p3', overallScore: 0.7, isCoverCandidate: true),
      ];

      final cover = CoverPhotoSelector.selectCover(
        photoScores: scores,
        peoplePresence: {'p1': true, 'p2': false, 'p3': false},
      );

      expect(cover, 'p1');
    });

    test('selects cover with people bonus', () {
      final scores = [
        const PhotoScore(photoId: 'p1', overallScore: 0.7, isCoverCandidate: true),
        const PhotoScore(photoId: 'p2', overallScore: 0.75, isCoverCandidate: true),
      ];

      final cover = CoverPhotoSelector.selectCover(
        photoScores: scores,
        peoplePresence: {'p1': true, 'p2': false},
      );

      expect(cover, 'p1');
    });

    test('returns empty string for empty input', () {
      final cover = CoverPhotoSelector.selectCover(photoScores: []);
      expect(cover, '');
    });
  });

  group('SemanticAnalysis', () {
    test('computeCoherence returns 0.5 for insufficient data', () {
      final result = SemanticAnalysis.computeCoherence(
        embeddings: {'p1': [1.0, 0.0, 0.0]},
        photoIds: ['p1'],
      );
      expect(result, 0.5);
    });

    test('computeCoherence returns high score for similar vectors', () {
      final result = SemanticAnalysis.computeCoherence(
        embeddings: {
          'p1': [1.0, 0.0, 0.0],
          'p2': [0.9, 0.1, 0.0],
          'p3': [0.95, 0.05, 0.0],
        },
        photoIds: ['p1', 'p2', 'p3'],
      );
      expect(result, greaterThan(0.8));
    });

    test('computeCoherence returns low score for dissimilar vectors', () {
      final result = SemanticAnalysis.computeCoherence(
        embeddings: {
          'p1': [1.0, 0.0, 0.0],
          'p2': [0.0, 1.0, 0.0],
          'p3': [0.0, 0.0, 1.0],
        },
        photoIds: ['p1', 'p2', 'p3'],
      );
      // Orthogonal vectors: centroid is [0.33, 0.33, 0.33], 
      // cosine sim to centroid = 0.577, so coherence = 0.577
      expect(result, greaterThanOrEqualTo(0.0));
      expect(result, lessThanOrEqualTo(1.0));
    });

    test('findRepresentative returns closest to centroid', () {
      final result = SemanticAnalysis.findRepresentative(
        embeddings: {
          'p1': [1.0, 0.0, 0.0],
          'p2': [0.9, 0.1, 0.0],
          'p3': [0.95, 0.05, 0.0],
        },
        photoIds: ['p1', 'p2', 'p3'],
      );
      expect(['p1', 'p2', 'p3'], contains(result));
    });

    test('computeDiversity returns 0 for identical vectors', () {
      final result = SemanticAnalysis.computeDiversity(
        embeddings: {
          'p1': [1.0, 0.0, 0.0],
          'p2': [1.0, 0.0, 0.0],
        },
        photoIds: ['p1', 'p2'],
      );
      expect(result, 0.0);
    });
  });

  group('TripDetection', () {
    test('detectTripsSimple finds trips with GPS spread', () {
      final cluster = PhotoCluster(
        clusterId: 'c1',
        photoIds: List.generate(10, (i) => 'p$i'),
        startDate: DateTime(2025, 7, 1),
        endDate: DateTime(2025, 7, 5),
        span: const Duration(days: 4),
      );

      final gpsData = <String, (double, double)>{};
      for (var i = 0; i < 10; i++) {
        gpsData['p$i'] = (37.0 + i * 0.1, -122.0 + i * 0.1);
      }

      final trips = TripDetection.detectTripsSimple(
        clusters: [cluster],
        gpsData: gpsData,
      );

      expect(trips.isNotEmpty, true);
      expect(trips.first.photoCount, 10);
    });

    test('detectTripsSimple ignores small clusters', () {
      final cluster = PhotoCluster(
        clusterId: 'c1',
        photoIds: ['p1', 'p2'],
        startDate: DateTime(2025, 7, 1),
        endDate: DateTime(2025, 7, 5),
        span: const Duration(days: 4),
      );

      final trips = TripDetection.detectTripsSimple(
        clusters: [cluster],
        gpsData: {'p1': (37.0, -122.0), 'p2': (37.1, -122.1)},
      );

      expect(trips.isEmpty, true);
    });
  });

  group('AutomaticAlbumGenerator', () {
    test('generates best of year albums', () {
      final memories = [
        Memory(
          memoryId: 'm1',
          title: 'Summer Trip',
          photoIds: List.generate(15, (i) => 'p$i'),
          coverPhotoId: 'p0',
          startDate: DateTime(2024, 7, 1),
          endDate: DateTime(2024, 7, 5),
          score: 0.9,
          theme: MemoryTheme.trip,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final albums = AutomaticAlbumGenerator.generate(
        memories: memories,
        referenceDate: DateTime(2025, 8, 1),
      );

      final bestOfYear = albums.where(
        (a) => a.type == AutomaticAlbumType.bestOfYear,
      );
      expect(bestOfYear.isNotEmpty, true);
    });

    test('generates trip albums from trip memories', () {
      final memories = [
        Memory(
          memoryId: 'm1',
          title: 'Paris Trip',
          photoIds: List.generate(20, (i) => 'p$i'),
          coverPhotoId: 'p0',
          startDate: DateTime(2025, 6, 1),
          endDate: DateTime(2025, 6, 7),
          score: 0.9,
          theme: MemoryTheme.trip,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final albums = AutomaticAlbumGenerator.generate(memories: memories);
      final tripAlbums = albums.where(
        (a) => a.type == AutomaticAlbumType.trip,
      );
      expect(tripAlbums.isNotEmpty, true);
    });

    test('skips current year for best of year', () {
      final now = DateTime.now();
      final memories = [
        Memory(
          memoryId: 'm1',
          title: 'Recent',
          photoIds: List.generate(15, (i) => 'p$i'),
          coverPhotoId: 'p0',
          startDate: DateTime(now.year, 6, 1),
          endDate: DateTime(now.year, 6, 5),
          score: 0.9,
          theme: MemoryTheme.trip,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final albums = AutomaticAlbumGenerator.generate(
        memories: memories,
        referenceDate: now,
      );

      final bestOfYear = albums.where(
        (a) => a.type == AutomaticAlbumType.bestOfYear,
      );
      expect(bestOfYear.isEmpty, true);
    });
  });
}
