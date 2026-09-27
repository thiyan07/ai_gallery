import '../../domain/models/memory/photo_score.dart';

/// Selects the best cover photo for a memory.
///
/// Cover photos should be high quality, visually representative,
/// and not blurry. They serve as the thumbnail for the memory.
class CoverPhotoSelector {
  /// Penalty for photos that are not "cover candidates".
  static const nonCandidatePenalty = 0.3;

  /// Bonus for photos with people (faces make better covers).
  static const peopleBonus = 0.15;

  /// Bonus for photos with good composition (landscape or portrait).
  static const compositionBonus = 0.1;

  /// Selects the best cover photo from a list of scored photos.
  ///
  /// [photoScores] — photos with their scores
  /// [peoplePresence] — map of photoId to whether people are present
  /// [aspectRatios] — map of photoId to (width, height) for composition check
  /// Returns the best cover photo ID.
  static String selectCover({
    required List<PhotoScore> photoScores,
    Map<String, bool>? peoplePresence,
    Map<String, (int, int)>? aspectRatios,
  }) {
    if (photoScores.isEmpty) return '';

    var bestPhoto = photoScores.first;
    var bestScore = -1.0;

    for (final photo in photoScores) {
      var score = photo.overallScore;

      // Penalty for non-candidates
      if (!photo.isCoverCandidate) {
        score -= nonCandidatePenalty;
      }

      // Bonus for people
      if (peoplePresence != null && peoplePresence[photo.photoId] == true) {
        score += peopleBonus;
      }

      // Bonus for good composition
      if (aspectRatios != null && aspectRatios.containsKey(photo.photoId)) {
        final (w, h) = aspectRatios[photo.photoId]!;
        if (_hasGoodComposition(w, h)) {
          score += compositionBonus;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestPhoto = photo;
      }
    }

    return bestPhoto.photoId;
  }

  /// Selects cover photos for multiple memories in batch.
  static Map<String, String> selectCoversBatch({
    required Map<String, List<PhotoScore>> memoryPhotos,
    Map<String, bool>? peoplePresence,
    Map<String, (int, int)>? aspectRatios,
  }) {
    final covers = <String, String>{};

    for (final entry in memoryPhotos.entries) {
      covers[entry.key] = selectCover(
        photoScores: entry.value,
        peoplePresence: peoplePresence,
        aspectRatios: aspectRatios,
      );
    }

    return covers;
  }

  static bool _hasGoodComposition(int width, int height) {
    if (width == 0 || height == 0) return false;
    final ratio = width / height;
    // Landscape (1.3-1.8) or Portrait (0.55-0.77) or Square (0.9-1.1)
    return (ratio >= 1.3 && ratio <= 1.8) ||
        (ratio >= 0.55 && ratio <= 0.77) ||
        (ratio >= 0.9 && ratio <= 1.1);
  }
}
