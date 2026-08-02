import 'dart:math';

import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/domain/models/photo_metadata.dart';
import 'package:ai_gallery/features/search/services/search_service.dart';

/// Engine for ranking search results using multiple signals.
///
/// Combines semantic similarity with metadata signals:
/// - Semantic similarity (cosine similarity)
/// - Favorites (boosted)
/// - Recency (recent photos slightly boosted)
/// - Quality score
/// - Usage frequency (recently viewed/edited)
/// - Album/folder relevance
class RankingEngine {
  RankingEngine({
    required this.database,
    AppLogger? logger,
  }) : _logger = logger;

  final AppDatabase database;
  final AppLogger? _logger;

  /// Weights for different ranking signals (sum should be ~1.0 for normalization)
  static const _weights = _RankingWeights(
    semanticSimilarity: 0.55,
    isFavorite: 0.15,
    recency: 0.10,
    qualityScore: 0.08,
    usageFrequency: 0.07,
    albumRelevance: 0.05,
  );

  /// Maximum age for recency boost (photos within this window get full recency score).
  static const _maxRecencyAge = Duration(days: 30);

  /// Ranks search results using multiple signals.
  ///
  /// [results] - Initial search results with semantic similarity scores.
  /// [context] - Optional ranking context (e.g., current album, user preferences).
  Future<List<RankedSearchResult>> rank(
    List<SearchResult> results, {
    RankingContext? context,
  }) async {
    if (results.isEmpty) return [];

    _logger?.debug('Ranking ${results.length} search results');

    // Fetch metadata for all results in batch
    final photoIds = results.map((r) => r.photoId).toList();
    final metadataMap = await _fetchMetadataBatch(photoIds);

    // Fetch favorite status in batch
    final favoriteMap = await _fetchFavoriteStatusBatch(photoIds);

    // Fetch usage stats in batch
    final usageMap = await _fetchUsageStatsBatch(photoIds);

    final ranked = <RankedSearchResult>[];
    for (final result in results) {
      final meta = metadataMap[result.photoId];
      final isFavorite = favoriteMap[result.photoId] ?? false;
      final usage = usageMap[result.photoId] ?? _UsageStats();

      final score = _calculateRankScore(
        semanticScore: result.score,
        metadata: meta,
        isFavorite: isFavorite,
        usage: usage,
        context: context,
      );

      ranked.add(RankedSearchResult(
        photoId: result.photoId,
        score: score,
        semanticScore: result.score,
        metadata: meta,
        isFavorite: isFavorite,
        viewCount: usage.viewCount,
        lastViewed: usage.lastViewed,
      ));
    }

    // Sort by final score descending
    ranked.sort((a, b) => b.score.compareTo(a.score));

    _logger?.debug('Ranked results: top=${ranked.isNotEmpty ? ranked.first.score.toStringAsFixed(3) : 'N/A'}');
    return ranked;
  }

  /// Calculates the final rank score for a single result.
  double _calculateRankScore({
    required double semanticScore,
    PhotoMetadata? metadata,
    required bool isFavorite,
    required _UsageStats usage,
    RankingContext? context,
  }) {
    final weights = _weights;

    // 1. Semantic similarity (0.0 - 1.0)
    final semantic = semanticScore.clamp(0.0, 1.0);

    // 2. Favorite boost (binary: 1.0 if favorite, 0.0 otherwise)
    final favorite = isFavorite ? 1.0 : 0.0;

    // 3. Recency (exponential decay: 1.0 for now, ~0.37 at 30 days, ~0.14 at 60 days)
    double recency = 0.0;
    if (metadata?.dateCreated != null) {
      final age = DateTime.now().difference(metadata!.dateCreated!);
      if (age.inDays <= 0) {
        recency = 1.0;
      } else {
        recency = exp(-age.inDays / _maxRecencyAge.inDays);
      }
    }

    // 4. Quality score (0.0 - 1.0 from metadata)
    final quality = (metadata?.qualityScore ?? 0.5).clamp(0.0, 1.0);

    // 5. Usage frequency (logarithmic: log(1 + views) / log(1 + maxViews))
    // Normalize to 0-1 based on typical max views
    final usageScore = min(1.0, log(1 + usage.viewCount) / log(1 + 100));

    // 6. Album relevance (1.0 if in current album/folder, 0.5 if in related, 0.0 otherwise)
    double albumRelevance = 0.0;
    if (context?.currentAlbumId != null && metadata?.albumId != null) {
      if (metadata!.albumId == context!.currentAlbumId) {
        albumRelevance = 1.0;
      } else if (context.relatedAlbumIds.contains(metadata.albumId)) {
        albumRelevance = 0.5;
      }
    }

    // Weighted sum
    final score =
        weights.semanticSimilarity * semantic +
        weights.isFavorite * favorite +
        weights.recency * recency +
        weights.qualityScore * quality +
        weights.usageFrequency * usageScore +
        weights.albumRelevance * albumRelevance;

    return score.clamp(0.0, 1.0);
  }

  /// Fetch metadata for multiple photo IDs in a single query.
  Future<Map<String, PhotoMetadata>> _fetchMetadataBatch(List<String> photoIds) async {
    if (photoIds.isEmpty) return {};

    final placeholders = photoIds.map((_) => '?').join(',');
    final rows = await database.database.rawQuery('''
      SELECT * FROM photo_metadata WHERE photo_id IN ($placeholders)
    ''', photoIds);

    final map = <String, PhotoMetadata>{};
    for (final row in rows) {
      final meta = PhotoMetadata.fromMap(row);
      map[meta.photoId] = meta;
    }
    return map;
  }

  /// Fetch favorite status for multiple photo IDs in a single query.
  Future<Map<String, bool>> _fetchFavoriteStatusBatch(List<String> photoIds) async {
    if (photoIds.isEmpty) return {};

    final placeholders = photoIds.map((_) => '?').join(',');
    final rows = await database.database.rawQuery('''
      SELECT asset_id FROM favorites WHERE asset_id IN ($placeholders)
    ''', photoIds);

    final set = <String>{};
    for (final row in rows) {
      set.add(row['asset_id'] as String);
    }

    return {for (final id in photoIds) id: set.contains(id)};
  }

  /// Fetch usage statistics for multiple photo IDs.
  Future<Map<String, _UsageStats>> _fetchUsageStatsBatch(List<String> photoIds) async {
    if (photoIds.isEmpty) return {};

    // Check if photo_usage table exists (may not exist yet)
    final tables = await database.database.rawQuery('''
      SELECT name FROM sqlite_master WHERE type='table' AND name='photo_usage'
    ''');

    if (tables.isEmpty) {
      // Table doesn't exist, return empty stats
      return {for (final id in photoIds) id: _UsageStats()};
    }

    final placeholders = photoIds.map((_) => '?').join(',');
    final rows = await database.database.rawQuery('''
      SELECT photo_id, view_count, last_viewed_at
      FROM photo_usage
      WHERE photo_id IN ($placeholders)
    ''', photoIds);

    final map = <String, _UsageStats>{};
    for (final row in rows) {
      map[row['photo_id'] as String] = _UsageStats(
        viewCount: row['view_count'] as int? ?? 0,
        lastViewed: row['last_viewed_at'] != null
            ? DateTime.parse(row['last_viewed_at'] as String)
            : null,
      );
    }

    // Fill missing with defaults
    for (final id in photoIds) {
      map.putIfAbsent(id, () => _UsageStats());
    }

    return map;
  }
}

/// Configuration for ranking weights.
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

/// Context for ranking (optional signals).
class RankingContext {
  const RankingContext({
    this.currentAlbumId,
    this.currentFolderId,
    this.userPreferenceWeights,
    this.relatedAlbumIds = const [],
  });

  /// Currently viewed album (boosts photos in this album).
  final String? currentAlbumId;

  /// Currently viewed folder (boosts photos in this folder).
  final String? currentFolderId;

  /// Related album IDs (e.g., same event, slightly boosted).
  final List<String> relatedAlbumIds;

  /// Custom weight overrides per user preferences.
  final Map<String, double>? userPreferenceWeights;
}

/// Search result with combined ranking score and signals.
class RankedSearchResult {
  const RankedSearchResult({
    required this.photoId,
    required this.score,
    required this.semanticScore,
    this.metadata,
    this.isFavorite = false,
    this.viewCount = 0,
    this.lastViewed,
  });

  final String photoId;
  final double score; // Final combined rank score (0.0 - 1.0)
  final double semanticScore; // Original semantic similarity
  final PhotoMetadata? metadata;
  final bool isFavorite;
  final int viewCount;
  final DateTime? lastViewed;

  /// Convert to SearchResult for backward compatibility.
  SearchResult toSearchResult() => SearchResult(
        photoId: photoId,
        score: score,
        metadata: metadata,
      );
}

/// Internal usage statistics.
class _UsageStats {
  const _UsageStats({this.viewCount = 0, this.lastViewed});

  final int viewCount;
  final DateTime? lastViewed;
}