import 'dart:math' as math;

import '../../domain/models/memory/photo_cluster.dart';
import '../../domain/models/memory/memory_candidate.dart';

/// Scores memory candidates based on multiple signals.
///
/// Produces a weighted overall score from temporal coherence, location,
/// people presence, semantic similarity, and photo quality.
class MemoryScoring {
  // Weight constants — tuned for balanced scoring
  static const temporalWeight = 0.25;
  static const locationWeight = 0.20;
  static const peopleWeight = 0.20;
  static const semanticWeight = 0.20;
  static const qualityWeight = 0.15;

  /// Minimum score threshold for a candidate to be kept.
  static const minOverallScore = 0.3;

  /// Scores a list of photo clusters as memory candidates.
  static List<MemoryCandidate> scoreCandidates({
    required List<PhotoCluster> clusters,
    Map<String, double>? qualityScores,
    Map<String, bool>? peoplePresence,
    Map<String, List<double>>? embeddings,
    Map<String, (double, double)>? gpsData,
  }) {
    final candidates = <MemoryCandidate>[];

    for (var i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      final candidate = _scoreSingle(
        candidateId: 'candidate_$i',
        cluster: cluster,
        qualityScores: qualityScores,
        peoplePresence: peoplePresence,
        embeddings: embeddings,
        gpsData: gpsData,
      );

      if (candidate.overallScore >= minOverallScore) {
        candidates.add(candidate);
      }
    }

    // Sort by overall score descending
    candidates.sort((a, b) => b.overallScore.compareTo(a.overallScore));

    // Mark duplicates
    return _markDuplicates(candidates);
  }

  static MemoryCandidate _scoreSingle({
    required String candidateId,
    required PhotoCluster cluster,
    Map<String, double>? qualityScores,
    Map<String, bool>? peoplePresence,
    Map<String, List<double>>? embeddings,
    Map<String, (double, double)>? gpsData,
  }) {
    final temporalScore = _scoreTemporal(cluster);
    final locationScore = _scoreLocation(cluster, gpsData);
    final peopleScore = _scorePeople(cluster, peoplePresence);
    final semanticScore = _scoreSemantic(cluster, embeddings);
    final qualityScore = _scoreQuality(cluster, qualityScores);

    final overall = temporalScore * temporalWeight +
        locationScore * locationWeight +
        peopleScore * peopleWeight +
        semanticScore * semanticWeight +
        qualityScore * qualityWeight;

    return MemoryCandidate(
      candidateId: candidateId,
      cluster: cluster,
      temporalScore: temporalScore,
      locationScore: locationScore,
      peopleScore: peopleScore,
      semanticScore: semanticScore,
      qualityScore: qualityScore,
      overallScore: overall,
    );
  }

  /// Temporal coherence: tighter clusters score higher.
  ///
  /// Single-day events with photos spread throughout the day score highest.
  /// Multi-day trips score based on consistent activity.
  static double _scoreTemporal(PhotoCluster cluster) {
    if (cluster.photoCount == 0) return 0.0;

    // Photo density: photos per hour
    final hours = math.max(cluster.span.inMinutes / 60.0, 1.0);
    final density = cluster.photoCount / hours;

    // Sweet spot: 2-20 photos per hour
    final densityScore = density >= 2.0 && density <= 20.0
        ? 1.0
        : density < 2.0
            ? density / 2.0
            : 1.0 - (density - 20.0) / 80.0;

    // Multi-day bonus for trips (2-7 days)
    final days = cluster.span.inDays;
    final durationScore = days == 0
        ? 1.0 // Single day
        : days >= 2 && days <= 7
            ? 0.9
            : days > 7
                ? 0.7
                : 0.5;

    return (densityScore * 0.6 + durationScore * 0.4).clamp(0.0, 1.0);
  }

  /// Location coherence: photos with consistent GPS score higher.
  static double _scoreLocation(PhotoCluster cluster, Map<String, (double, double)>? gpsData) {
    if (gpsData == null || cluster.photoIds.isEmpty) return 0.5;

    final locations = cluster.photoIds
        .where((id) => gpsData.containsKey(id))
        .map((id) => gpsData[id]!)
        .toList();

    if (locations.isEmpty) return 0.3;

    final gpsRatio = locations.length / cluster.photoCount;

    // If most photos have GPS, check location spread
    if (gpsRatio > 0.5) {
      final spread = _calculateLocationSpread(locations);
      // Tight cluster (< 0.01 degrees ~ 1km) = high score
      // Wide spread (> 0.1 degrees ~ 10km) = trip, still valid
      if (spread < 0.01) return 1.0;
      if (spread < 0.05) return 0.9;
      if (spread < 0.1) return 0.8;
      return 0.7; // Wide spread — still a valid trip
    }

    return gpsRatio;
  }

  /// People presence: photos with known people score higher.
  static double _scorePeople(PhotoCluster cluster, Map<String, bool>? peoplePresence) {
    if (peoplePresence == null || cluster.photoIds.isEmpty) return 0.3;

    final withPeople = cluster.photoIds
        .where((id) => peoplePresence[id] == true)
        .length;

    final ratio = withPeople / cluster.photoCount;

    // Some people present = good, all people = great
    if (ratio >= 0.5) return 1.0;
    if (ratio >= 0.2) return 0.8;
    if (ratio > 0) return 0.6;
    return 0.3;
  }

  /// Semantic coherence: how similar are the photos to each other?
  static double _scoreSemantic(PhotoCluster cluster, Map<String, List<double>>? embeddings) {
    if (embeddings == null || cluster.photoIds.length < 2) return 0.5;

    final vectors = cluster.photoIds
        .where((id) => embeddings.containsKey(id))
        .map((id) => embeddings[id]!)
        .toList();

    if (vectors.length < 2) return 0.5;

    // Compute average pairwise cosine similarity
    var totalSim = 0.0;
    var count = 0;

    for (var i = 0; i < vectors.length; i++) {
      for (var j = i + 1; j < vectors.length; j++) {
        totalSim += _cosineSimilarity(vectors[i], vectors[j]);
        count++;
      }
    }

    return count > 0 ? (totalSim / count).clamp(0.0, 1.0) : 0.5;
  }

  /// Photo quality: average quality of photos in the cluster.
  static double _scoreQuality(PhotoCluster cluster, Map<String, double>? qualityScores) {
    if (qualityScores == null || cluster.photoIds.isEmpty) return 0.5;

    final scores = cluster.photoIds
        .where((id) => qualityScores.containsKey(id))
        .map((id) => qualityScores[id]!)
        .toList();

    if (scores.isEmpty) return 0.5;

    // Use average of top 70% of photos (ignore worst 30%)
    final sorted = List<double>.from(scores)..sort((a, b) => b.compareTo(a));
    final keepCount = math.max(1, (sorted.length * 0.7).ceil());
    final topScores = sorted.sublist(0, keepCount);

    return topScores.reduce((a, b) => a + b) / topScores.length;
  }

  static double _calculateLocationSpread(List<(double, double)> locations) {
    if (locations.length < 2) return 0.0;

    final lats = locations.map((l) => l.$1).toList();
    final lngs = locations.map((l) => l.$2).toList();

    final latRange = lats.reduce(math.max) - lats.reduce(math.min);
    final lngRange = lngs.reduce(math.max) - lngs.reduce(math.min);

    return math.max(latRange, lngRange);
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = math.sqrt(normA) * math.sqrt(normB);
    return denominator == 0 ? 0.0 : dotProduct / denominator;
  }

  static List<MemoryCandidate> _markDuplicates(List<MemoryCandidate> candidates) {
    final photoToCandidate = <String, int>{};

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      var overlapCount = 0;

      for (final photoId in candidate.photoIds) {
        if (photoToCandidate.containsKey(photoId)) {
          overlapCount++;
        }
      }

      final overlapRatio = candidate.photoCount > 0
          ? overlapCount / candidate.photoCount
          : 0.0;

      if (overlapRatio > 0.7) {
        candidates[i] = candidate.copyWith(isDuplicate: true);
      }

      for (final photoId in candidate.photoIds) {
        photoToCandidate[photoId] = i;
      }
    }

    return candidates;
  }
}
