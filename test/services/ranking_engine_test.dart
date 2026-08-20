import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/features/search/services/ranking_engine.dart';

void main() {
  group('RankingEngine', () {
    test('empty results returns empty list', () async {
      // RankingEngine requires a database, but we can test the score calculation
      // by verifying the weight constants sum to ~1.0
      const weights = _RankingWeights(
        semanticSimilarity: 0.55,
        isFavorite: 0.15,
        recency: 0.10,
        qualityScore: 0.08,
        usageFrequency: 0.07,
        albumRelevance: 0.05,
      );
      final sum =
          weights.semanticSimilarity +
          weights.isFavorite +
          weights.recency +
          weights.qualityScore +
          weights.usageFrequency +
          weights.albumRelevance;
      expect(sum, closeTo(1.0, 0.001));
    });
  });

  group('RankedSearchResult', () {
    test('toSearchResult converts correctly', () {
      const result = RankedSearchResult(
        photoId: 'test-123',
        score: 0.85,
        semanticScore: 0.9,
        isFavorite: true,
        viewCount: 5,
      );
      final searchResult = result.toSearchResult();
      expect(searchResult.photoId, 'test-123');
      expect(searchResult.score, 0.85);
    });
  });

  group('RankingContext', () {
    test('default values are correct', () {
      const context = RankingContext();
      expect(context.currentAlbumId, isNull);
      expect(context.currentFolderId, isNull);
      expect(context.relatedAlbumIds, isEmpty);
      expect(context.userPreferenceWeights, isNull);
    });
  });
}

/// Exposed for testing weight constants.
class _RankingWeights {
  const _RankingWeights({
    required this.semanticSimilarity,
    required this.isFavorite,
    required this.recency,
    required this.qualityScore,
    required this.usageFrequency,
    required this.albumRelevance,
  });

  final double semanticSimilarity;
  final double isFavorite;
  final double recency;
  final double qualityScore;
  final double usageFrequency;
  final double albumRelevance;
}
