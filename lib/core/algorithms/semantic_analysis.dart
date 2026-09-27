import 'dart:math' as math;

/// Analyzes semantic coherence within a photo cluster using embeddings.
///
/// Computes how semantically similar photos are to each other,
/// detects sub-themes within a cluster, and identifies representative photos.
class SemanticAnalysis {
  /// Threshold for considering two photos semantically similar.
  static const similarityThreshold = 0.6;

  /// Minimum similarity to cluster centroid for a photo to be "in-theme".
  static const inThemeThreshold = 0.4;

  /// Computes semantic coherence score for a cluster of photos.
  ///
  /// [embeddings] — map of photoId to embedding vector
  /// [photoIds] — photo IDs in the cluster
  /// Returns a score from 0.0 (no coherence) to 1.0 (highly coherent).
  static double computeCoherence({
    required Map<String, List<double>> embeddings,
    required List<String> photoIds,
  }) {
    final vectors = photoIds
        .where((id) => embeddings.containsKey(id))
        .map((id) => embeddings[id]!)
        .toList();

    if (vectors.length < 2) return 0.5;

    // Compute centroid
    final centroid = _computeCentroid(vectors);

    // Compute average distance to centroid
    var totalDistance = 0.0;
    for (final vector in vectors) {
      totalDistance += 1.0 - _cosineSimilarity(centroid, vector);
    }

    final avgDistance = totalDistance / vectors.length;

    // Convert distance to coherence score (lower distance = higher coherence)
    return (1.0 - avgDistance).clamp(0.0, 1.0);
  }

  /// Detects sub-themes within a cluster by looking for semantic gaps.
  ///
  /// Returns a list of sub-groups, each being a list of photo IDs.
  static List<List<String>> detectSubThemes({
    required Map<String, List<double>> embeddings,
    required List<String> photoIds,
    int minSubGroupSize = 3,
  }) {
    if (photoIds.length < minSubGroupSize * 2) {
      return [photoIds];
    }

    final vectors = <String, List<double>>{};
    for (final id in photoIds) {
      if (embeddings.containsKey(id)) {
        vectors[id] = embeddings[id]!;
      }
    }

    if (vectors.length < minSubGroupSize * 2) {
      return [photoIds];
    }

    // Compute pairwise similarity matrix
    final ids = vectors.keys.toList();
    final n = ids.length;
    final similarity = List.generate(n, (_) => List.filled(n, 0.0));

    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final sim = _cosineSimilarity(vectors[ids[i]]!, vectors[ids[j]]!);
        similarity[i][j] = sim;
        similarity[j][i] = sim;
      }
    }

    // Simple clustering: group photos with avg pairwise sim > threshold
    final assigned = List.filled(n, false);
    final groups = <List<String>>[];

    for (var i = 0; i < n; i++) {
      if (assigned[i]) continue;

      final group = [ids[i]];
      assigned[i] = true;

      for (var j = i + 1; j < n; j++) {
        if (assigned[j]) continue;

        // Check avg similarity to current group
        var totalSim = 0.0;
        for (final groupId in group) {
          final groupIdx = ids.indexOf(groupId);
          totalSim += similarity[groupIdx][j];
        }
        final avgSim = totalSim / group.length;

        if (avgSim >= similarityThreshold) {
          group.add(ids[j]);
          assigned[j] = true;
        }
      }

      if (group.length >= minSubGroupSize) {
        groups.add(group);
      }
    }

    // If no sub-groups found, return the whole cluster
    return groups.isEmpty ? [photoIds] : groups;
  }

  /// Finds the most representative photo in a cluster (closest to centroid).
  static String findRepresentative({
    required Map<String, List<double>> embeddings,
    required List<String> photoIds,
  }) {
    final vectors = <String, List<double>>{};
    for (final id in photoIds) {
      if (embeddings.containsKey(id)) {
        vectors[id] = embeddings[id]!;
      }
    }

    if (vectors.isEmpty) return photoIds.first;

    final centroid = _computeCentroid(vectors.values.toList());

    var bestId = vectors.keys.first;
    var bestSim = -1.0;

    for (final entry in vectors.entries) {
      final sim = _cosineSimilarity(centroid, entry.value);
      if (sim > bestSim) {
        bestSim = sim;
        bestId = entry.key;
      }
    }

    return bestId;
  }

  /// Computes diversity score — how varied are the photos in a cluster.
  ///
  /// High diversity = many different subjects/scenes.
  /// Low diversity = photos are very similar (e.g., burst shots).
  static double computeDiversity({
    required Map<String, List<double>> embeddings,
    required List<String> photoIds,
  }) {
    final vectors = photoIds
        .where((id) => embeddings.containsKey(id))
        .map((id) => embeddings[id]!)
        .toList();

    if (vectors.length < 2) return 0.0;

    // Compute average pairwise distance
    var totalDist = 0.0;
    var count = 0;

    for (var i = 0; i < vectors.length; i++) {
      for (var j = i + 1; j < vectors.length; j++) {
        totalDist += 1.0 - _cosineSimilarity(vectors[i], vectors[j]);
        count++;
      }
    }

    return count > 0 ? (totalDist / count).clamp(0.0, 1.0) : 0.0;
  }

  static List<double> _computeCentroid(List<List<double>> vectors) {
    if (vectors.isEmpty) return [];
    final dim = vectors.first.length;
    final centroid = List.filled(dim, 0.0);

    for (final vector in vectors) {
      for (var i = 0; i < dim; i++) {
        centroid[i] += vector[i];
      }
    }

    for (var i = 0; i < dim; i++) {
      centroid[i] /= vectors.length;
    }

    return centroid;
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
}
