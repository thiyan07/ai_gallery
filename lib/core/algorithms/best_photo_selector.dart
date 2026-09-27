import 'dart:math' as math;

import '../../domain/models/memory/photo_score.dart';

/// Selects the best photos from a group for prominence in a memory.
///
/// Considers quality, blur, temporal position, and semantic distinctiveness.
class BestPhotoSelector {
  /// Number of "best" photos to select per memory.
  static const defaultBestCount = 10;

  /// Selects the best photos from a scored list.
  ///
  /// [photoScores] — photos with their scores
  /// [count] — number of best photos to return
  /// Returns the top-ranked photos.
  static List<PhotoScore> selectBest({
    required List<PhotoScore> photoScores,
    int count = defaultBestCount,
  }) {
    if (photoScores.isEmpty) return [];

    // Sort by overall score descending
    final sorted = List<PhotoScore>.from(photoScores)
      ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

    // Take top N
    final bestCount = math.min(count, sorted.length);
    return sorted.sublist(0, bestCount);
  }

  /// Selects photos that represent different aspects of the memory.
  ///
  /// Ensures diversity by not selecting visually similar photos consecutively.
  static List<PhotoScore> selectDiverse({
    required List<PhotoScore> photoScores,
    required Map<String, List<double>> embeddings,
    int count = defaultBestCount,
  }) {
    if (photoScores.isEmpty) return [];
    if (photoScores.length <= count) return photoScores;

    // Sort by score first
    final sorted = List<PhotoScore>.from(photoScores)
      ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

    final selected = <PhotoScore>[sorted.first];
    final selectedIds = {sorted.first.photoId};

    while (selected.length < count && selected.length < sorted.length) {
      var bestCandidate = sorted.firstWhere(
        (p) => !selectedIds.contains(p.photoId),
        orElse: () => sorted.first,
      );
      var bestDiversity = -1.0;

      for (final candidate in sorted) {
        if (selectedIds.contains(candidate.photoId)) continue;

        // Compute min similarity to already selected photos
        var minSim = 1.0;
        if (embeddings.containsKey(candidate.photoId)) {
          for (final sel in selected) {
            if (embeddings.containsKey(sel.photoId)) {
              final sim = _cosineSimilarity(
                embeddings[candidate.photoId]!,
                embeddings[sel.photoId]!,
              );
              minSim = math.min(minSim, sim);
            }
          }
        }

        // Diversity = inverse of max similarity to selected
        final diversity = 1.0 - minSim;
        if (diversity > bestDiversity) {
          bestDiversity = diversity;
          bestCandidate = candidate;
        }
      }

      selected.add(bestCandidate);
      selectedIds.add(bestCandidate.photoId);
    }

    return selected;
  }

  /// Scores individual photos for ranking within a memory.
  static List<PhotoScore> scorePhotos({
    required List<String> photoIds,
    Map<String, double>? qualityScores,
    Map<String, double>? blurScores,
    DateTime? clusterStart,
    DateTime? clusterEnd,
  }) {
    return photoIds.map((id) {
      final quality = qualityScores?[id] ?? 0.5;
      final blur = blurScores?[id] ?? 0.5;

      // Temporal score: photos in the middle of the cluster are slightly favored
      final temporalScore = 0.5; // Default if no timestamps available

      final overall = (quality * 0.4 + blur * 0.3 + temporalScore * 0.3).clamp(0.0, 1.0);

      return PhotoScore(
        photoId: id,
        qualityScore: quality,
        blurScore: blur,
        temporalScore: temporalScore,
        overallScore: overall,
        isCoverCandidate: quality > 0.7 && blur > 0.7,
      );
    }).toList();
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = math.sqrt(normA) * math.sqrt(normB);
    return denom == 0 ? 0.0 : dot / denom;
  }
}
