import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/domain/models/embedding.dart';
import 'package:ai_gallery/domain/models/photo_metadata.dart';
import 'package:ai_gallery/features/search/services/natural_language_parser.dart';
import 'package:ai_gallery/features/search/services/ranking_engine.dart';
import 'package:ai_gallery/features/search/services/search_suggestion_service.dart';

/// Result of a search query.
class SearchResult {
  const SearchResult({
    required this.photoId,
    required this.score,
    this.metadata,
    this.thumbnailUrl,
    this.objectScore,
    this.videoSegmentTimestampMs,
  });

  final String photoId;
  final double score;
  final PhotoMetadata? metadata;
  final String? thumbnailUrl;

  /// Object tag confidence score (0.0 - 1.0, null if object filter not used).
  final double? objectScore;

  /// For video results: timestamp in ms of the matching segment, if applicable.
  final int? videoSegmentTimestampMs;

  /// Whether this result is a video.
  bool get isVideo => metadata?.mediaType == 'video';
}

/// Search filters for refining results.
/// Intent behind a search query, used to select the optimal search path.
enum SearchIntent {
  /// Query is primarily searching for a specific person.
  person,

  /// Query is searching for specific objects (YOLO-detected).
  object,

  /// Query is searching for scene/semantic concepts (embedding-based).
  scene,

  /// Query is searching for photos at a location.
  location,

  /// Query is primarily date-based.
  date,

  /// Query combines multiple signals (person+object, scene+date, etc.).
  combined,

  /// Query intent could not be determined; use default hybrid path.
  unknown,
}

class SearchFilters {
  const SearchFilters({
    this.dateFrom,
    this.dateTo,
    this.minQualityScore,
    this.maxBlurScore,
    this.hasLocation = false,
    this.cameraMake,
    this.cameraModel,
    this.albumId,
    this.folderPath,
    this.mediaType,
    this.orientation,
    this.favoritesOnly = false,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    this.personName,
    this.objectTags = const [],
    this.sceneConcepts = const [],
    this.locationLabel,
    this.excludeTags = const [],
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final double? minQualityScore;
  final double? maxBlurScore;
  final bool hasLocation;
  final String? cameraMake;
  final String? cameraModel;
  final String? albumId;
  final String? folderPath;
  final String? mediaType; // 'image', 'video', etc.
  final int? orientation; // 1-8 EXIF orientation
  final bool favoritesOnly;
  final int? minWidth;
  final int? maxWidth;
  final int? minHeight;
  final int? maxHeight;
  final String? personName;

  /// Object labels to match (from YOLO detections). Treated as hard filter
  /// when non-empty; photos must contain at least one of these objects.
  final List<String> objectTags;

  /// Scene/semantic concepts for ranking boost (embedding similarity).
  /// E.g. ['beach', 'sunset'] — not used as hard filter but boost ranking.
  final List<String> sceneConcepts;

  /// Human-readable location label (e.g. "Paris", "New York").
  /// Used for GPS-based location matching against photo_metadata lat/lng.
  final String? locationLabel;

  /// Object tags to explicitly exclude from results.
  final List<String> excludeTags;

  SearchFilters copyWith({
    Object? dateFrom = _sentinel,
    Object? dateTo = _sentinel,
    Object? minQualityScore = _sentinel,
    Object? maxBlurScore = _sentinel,
    bool? hasLocation,
    Object? cameraMake = _sentinel,
    Object? cameraModel = _sentinel,
    Object? albumId = _sentinel,
    Object? folderPath = _sentinel,
    Object? mediaType = _sentinel,
    Object? orientation = _sentinel,
    bool? favoritesOnly,
    Object? minWidth = _sentinel,
    Object? maxWidth = _sentinel,
    Object? minHeight = _sentinel,
    Object? maxHeight = _sentinel,
    Object? personName = _sentinel,
    Object? objectTags = _sentinel,
    Object? sceneConcepts = _sentinel,
    Object? locationLabel = _sentinel,
    Object? excludeTags = _sentinel,
  }) {
    return SearchFilters(
      dateFrom: dateFrom == _sentinel ? this.dateFrom : dateFrom as DateTime?,
      dateTo: dateTo == _sentinel ? this.dateTo : dateTo as DateTime?,
      minQualityScore: minQualityScore == _sentinel ? this.minQualityScore : minQualityScore as double?,
      maxBlurScore: maxBlurScore == _sentinel ? this.maxBlurScore : maxBlurScore as double?,
      hasLocation: hasLocation ?? this.hasLocation,
      cameraMake: cameraMake == _sentinel ? this.cameraMake : cameraMake as String?,
      cameraModel: cameraModel == _sentinel ? this.cameraModel : cameraModel as String?,
      albumId: albumId == _sentinel ? this.albumId : albumId as String?,
      folderPath: folderPath == _sentinel ? this.folderPath : folderPath as String?,
      mediaType: mediaType == _sentinel ? this.mediaType : mediaType as String?,
      orientation: orientation == _sentinel ? this.orientation : orientation as int?,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      minWidth: minWidth == _sentinel ? this.minWidth : minWidth as int?,
      maxWidth: maxWidth == _sentinel ? this.maxWidth : maxWidth as int?,
      minHeight: minHeight == _sentinel ? this.minHeight : minHeight as int?,
      maxHeight: maxHeight == _sentinel ? this.maxHeight : maxHeight as int?,
      personName: personName == _sentinel ? this.personName : personName as String?,
      objectTags: objectTags == _sentinel ? this.objectTags : objectTags as List<String>,
      sceneConcepts: sceneConcepts == _sentinel ? this.sceneConcepts : sceneConcepts as List<String>,
      locationLabel: locationLabel == _sentinel ? this.locationLabel : locationLabel as String?,
      excludeTags: excludeTags == _sentinel ? this.excludeTags : excludeTags as List<String>,
    );
  }

  static const _sentinel = Object();

  /// Whether any filters are active (excluding pagination/fulltext).
  bool get hasActiveFilters =>
      dateFrom != null ||
      dateTo != null ||
      minQualityScore != null ||
      maxBlurScore != null ||
      hasLocation ||
      cameraMake != null ||
      cameraModel != null ||
      albumId != null ||
      folderPath != null ||
      mediaType != null ||
      orientation != null ||
      favoritesOnly ||
      minWidth != null ||
      maxWidth != null ||
      minHeight != null ||
      maxHeight != null ||
      personName != null ||
      objectTags.isNotEmpty ||
      sceneConcepts.isNotEmpty ||
      locationLabel != null ||
      excludeTags.isNotEmpty;

  /// Whether any object-based filters are active.
  bool get hasObjectFilters => objectTags.isNotEmpty || excludeTags.isNotEmpty;

  /// Whether any location-based filter is active.
  bool get hasLocationFilter => locationLabel != null || hasLocation;

  /// Whether any scene concept is specified for ranking.
  bool get hasSceneConcepts => sceneConcepts.isNotEmpty;
}

/// Service for performing semantic search over photo embeddings.
class SearchService {
  SearchService({
    required this.embeddingProvider,
    required this.database,
    required this.rankingEngine,
    required this.suggestionService,
    AppLogger? logger,
  }) : _logger = logger ?? const ConsoleAppLogger();

  final EmbeddingProvider embeddingProvider;
  final AppDatabase database;
  final RankingEngine rankingEngine;
  final SearchSuggestionService suggestionService;
  final AppLogger _logger;

  /// In-memory cache of embeddings for fast search.
  final Map<String, Embedding> _embeddingCache = {};

  /// Maximum embeddings to cache in memory (conservative: ~15MB for 5000 × 3KB).
  static const _maxCacheSize = 5000;

  /// Tracks the model ID the cache was last populated for.
  String? _cachedModelId;

  /// The active model ID for filtering embeddings.
  String get _activeModelId => embeddingProvider.modelId;

  /// Performs a hybrid search (semantic + OCR text) with ranking.
  Future<List<RankedSearchResult>> search(
    String query, {
    int limit = 20,
    SearchFilters? filters,
    EmbeddingProvider? customProvider,
    RankingContext? rankingContext,
    bool recordSuggestion = true,
  }) async {
    if (query.trim().isEmpty) return [];

    final provider = customProvider ?? embeddingProvider;

    _logger.info('Searching for text query');

    // Record search suggestion
    if (recordSuggestion) {
      unawaited(suggestionService.recordSearch(query));
    }

    // Generate text embedding for query (semantic search) — gracefully degrade
    // to OCR-only if text model not ready (allows search to still work via OCR).
    Float32List? queryEmbedding;
    final Map<String, double> semanticScores = {};
    final queryTokenSet = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet();
    try {
      queryEmbedding = await provider.generateTextEmbedding(query);
      final semanticCandidates = await _getCandidateEmbeddings(filters);
      final scored = _scoreCandidates(
        queryEmbedding,
        semanticCandidates,
        queryTokens: queryTokenSet,
      );
      semanticScores.addAll(scored.scores);
    } on StateError catch (e) {
      if (e.message.contains('MODEL_NOT_READY')) {
        _logger.warning('Semantic search unavailable, falling back to OCR-only: $e');
      } else {
        rethrow;
      }
    } catch (e) {
      // Native init failures (e.g. missing libonnxruntime.so on x86_64
      // emulator) must also fall back to OCR-only, never crash search.
      _logger.warning('Semantic search unavailable (embedding init failed), falling back to OCR-only: $e');
    }

    // Get OCR text matches for the query
    final ocrRecords = await database.ocrResults.searchOcrText(query);
    // Build a map of photoId to text-match relevance score.
    // We combine the OCR recognition confidence (how reliable the text is)
    // with the query-relevance (how much of the query actually appears in
    // the OCR text), so a high-confidence OCR of unrelated text does not
    // unfairly outrank a lower-confidence but on-topic match.
    final Map<String, double> ocrTextScoreMap = {};
    final queryTokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    for (final record in ocrRecords) {
      final textLower = record.text.toLowerCase();
      double relevance;
      if (queryTokens.isEmpty) {
        relevance = textLower.contains(query.toLowerCase()) ? 1.0 : 0.0;
      } else {
        final matched = queryTokens.where(textLower.contains).length;
        relevance = matched / queryTokens.length;
      }
      final score = relevance * record.confidence.clamp(0.0, 1.0);
      final current = ocrTextScoreMap[record.photoId];
      if (current == null || score > current) {
        ocrTextScoreMap[record.photoId] = score;
      }
    }

    // Combine candidate photoIds from semantic search and OCR text matches
    final Set<String> allCandidateIds = <String>{};
    allCandidateIds.addAll(semanticScores.keys);
    allCandidateIds.addAll(ocrTextScoreMap.keys);

    // Weights for combining scores (can be tuned)
    const double semanticWeight = 0.7;
    const double textWeight = 0.3;

    // Build hybrid search results with batch metadata query (fix N+1)
    final candidateList = allCandidateIds.toList();
    final metadataMap = await database.photoMetadata.getByIds(candidateList);

    // Batch favorites check to avoid N+1 per-candidate queries
    Set<String>? favoriteIds;
    if (filters?.favoritesOnly == true) {
      favoriteIds = await database.favorites.filterFavorites(allCandidateIds);
    }

    final results = <SearchResult>[];
    for (final photoId in candidateList) {
      // Get metadata for filtering and result
      final meta = metadataMap[photoId];
      if (meta == null) {
        // Skip if no metadata (should not happen for indexed photos, but safe)
        continue;
      }

      // Apply filters (sync, uses batched favoriteIds)
      if (filters != null && !_matchesFiltersSync(meta, filters, favoriteIds: favoriteIds)) {
        continue;
      }
      // Skip if location required but none available
      if (filters?.hasLocation == true &&
          (meta.latitude == null || meta.longitude == null)) {
        continue;
      }

      // Get semantic score (default 0.0 if not in semantic candidates)
      final semanticScore = semanticScores[photoId] ?? 0.0;
      // Get OCR text match score (default 0.0 if no OCR match for this photo)
      final textMatchScore = ocrTextScoreMap[photoId] ?? 0.0;

      // Combine scores
      final double combinedScore =
          (semanticScore * semanticWeight) + (textMatchScore * textWeight);

      results.add(
        SearchResult(photoId: photoId, score: combinedScore, metadata: meta),
      );
    }

    // Sort by combined score descending
    results.sort((a, b) => b.score.compareTo(a.score));

    // Apply ranking engine (using the combined score as the initial score)
    // Intent-aware weights: plain search is scene-like
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(), // Get more candidates for ranking
      context: rankingContext,
      intent: SearchIntent.scene,
    );

    // Apply limit after ranking
    return rankedResults.take(limit).toList();
  }

  /// Checks if metadata matches all active filters.
  /// Note: favoritesOnly is handled via batch filtering in callers to avoid N+1;
  /// this method remains sync and rejects non-favorite via caller-provided set.
  bool _matchesFiltersSync(
    PhotoMetadata meta,
    SearchFilters filters, {
    Set<String>? favoriteIds,
  }) {
    if (filters.minQualityScore != null &&
        (meta.qualityScore ?? 0) < filters.minQualityScore!) {
      return false;
    }
    if (filters.maxBlurScore != null &&
        (meta.blurScore ?? 1.0) > filters.maxBlurScore!) {
      return false;
    }
    if (filters.dateFrom != null || filters.dateTo != null) {
      if (meta.dateCreated != null) {
        if (filters.dateFrom != null &&
            meta.dateCreated!.isBefore(filters.dateFrom!)) {
          return false;
        }
        if (filters.dateTo != null &&
            meta.dateCreated!.isAfter(filters.dateTo!)) {
          return false;
        }
      }
    }
    if (filters.hasLocation == true &&
        (meta.latitude == null || meta.longitude == null)) {
      return false;
    }
    if (filters.cameraMake != null && meta.cameraMake != filters.cameraMake) {
      return false;
    }
    if (filters.cameraModel != null &&
        meta.cameraModel != filters.cameraModel) {
      return false;
    }
    if (filters.albumId != null && meta.albumId != filters.albumId) {
      return false;
    }
    if (filters.folderPath != null && meta.folderPath != filters.folderPath) {
      return false;
    }
    if (filters.mediaType != null && meta.mediaType != filters.mediaType) {
      return false;
    }
    if (filters.orientation != null &&
        meta.orientation != filters.orientation) {
      return false;
    }
    if (filters.minWidth != null && meta.width < filters.minWidth!) {
      return false;
    }
    if (filters.maxWidth != null && meta.width > filters.maxWidth!) {
      return false;
    }
    if (filters.minHeight != null && meta.height < filters.minHeight!) {
      return false;
    }
    if (filters.maxHeight != null && meta.height > filters.maxHeight!) {
      return false;
    }
    if (filters.favoritesOnly == true) {
      if (favoriteIds != null) {
        if (!favoriteIds.contains(meta.photoId)) return false;
      } else {
        // No batch set provided — caller should have filtered; treat as non-match
        // to avoid per-row query. Keeping async fallback via wrapper below.
        return false;
      }
    }
    return true;
  }

  /// Async wrapper for callers that haven't batched favorites yet.
  Future<bool> _matchesFilters(
    PhotoMetadata meta,
    SearchFilters filters,
  ) async {
    if (filters.favoritesOnly == true) {
      final isFavorite = await database.favorites.isFavorite(meta.photoId);
      if (!isFavorite) return false;
      // Re-check remaining filters synchronously
      return _matchesFiltersSync(meta, filters, favoriteIds: {meta.photoId});
    }
    return _matchesFiltersSync(meta, filters);
  }

  /// Performs a search using a pre-parsed natural language query.
  ///
  /// Handles all multi-signal combinations:
  /// - Person-only: fast DB lookup via face relationships
  /// - Object-only: YOLO object tag matching
  /// - Scene-only: embedding similarity search
  /// - Location-only: GPS proximity search
  /// - Person + Semantic: person filter → semantic ranking
  /// - Object + Semantic: object filter → semantic ranking
  /// - Person + Object + Semantic: person + object → semantic ranking
  /// - Any combination with date/camera/quality filters
  /// Parsed-query search with relevance-feedback filtering.
  ///
  /// Photos the user marked "not relevant" for this exact query are hidden.
  Future<List<RankedSearchResult>> searchParsed(
    ParsedQuery parsedQuery, {
    int limit = 20,
    RankingContext? rankingContext,
    bool recordSuggestion = true,
  }) async {
    final results = await _searchParsedInner(
      parsedQuery,
      limit: limit,
      rankingContext: rankingContext,
      recordSuggestion: recordSuggestion,
    );
    final query = parsedQuery.originalQuery ?? parsedQuery.semanticQuery;
    if (query.trim().isEmpty) return results;
    final disliked = await database.searchFeedback.dislikedForQuery(query);
    if (disliked.isEmpty) return results;
    return results.where((r) => !disliked.contains(r.photoId)).toList();
  }

  /// Record that [photoId] is not relevant for [query] (hides it from future
  /// runs of that query).
  Future<void> markNotRelevant(String photoId, String query) =>
      database.searchFeedback.markNotRelevant(photoId, query);

  /// Undo a "not relevant" mark.
  Future<void> clearNotRelevant(String photoId, String query) =>
      database.searchFeedback.clearMark(photoId, query);

  Future<List<RankedSearchResult>> _searchParsedInner(
    ParsedQuery parsedQuery, {
    int limit = 20,
    RankingContext? rankingContext,
    bool recordSuggestion = true,
  }) async {
    final hasSemanticQuery = parsedQuery.semanticQuery.trim().isNotEmpty;
    final hasPersonFilter = parsedQuery.filters.personName != null;
    final hasObjectFilter = parsedQuery.filters.objectTags.isNotEmpty;
    final hasLocationFilter = parsedQuery.filters.locationLabel != null;

    if (!hasSemanticQuery && !hasPersonFilter && !hasObjectFilter && !hasLocationFilter) return [];

    _logger.info(
      'Searching with parsed query'
      ' (intent: ${parsedQuery.intent.name}, confidence: ${parsedQuery.confidence})',
    );

    // Record search suggestion
    if (recordSuggestion) {
      unawaited(
        suggestionService.recordSearch(
          parsedQuery.originalQuery ?? parsedQuery.semanticQuery,
        ),
      );
    }

    // ─── PERSON-ONLY PATH (no semantic query, no object filter) ──────
    if (!hasSemanticQuery && hasPersonFilter && !hasObjectFilter) {
      return searchByPerson(
        parsedQuery.filters.personName!,
        limit: limit,
        filters: parsedQuery.filters,
        rankingContext: rankingContext,
      );
    }

    // ─── OBJECT-ONLY PATH (no semantic query, no person filter) ──────
    if (!hasSemanticQuery && hasObjectFilter && !hasPersonFilter) {
      return _searchObjectOnly(
        parsedQuery,
        limit: limit,
        rankingContext: rankingContext,
      );
    }

    // ─── LOCATION-ONLY PATH (no semantic query) ──────────────────────
    if (!hasSemanticQuery && hasLocationFilter && !hasPersonFilter && !hasObjectFilter) {
      return _searchLocationOnly(
        parsedQuery,
        limit: limit,
        rankingContext: rankingContext,
      );
    }

    // ─── PERSON + SEMANTIC (and optionally object/date/OCR) ──────────
    if (hasPersonFilter && hasSemanticQuery) {
      return _searchPersonWithSemantic(
        parsedQuery,
        limit: limit,
        rankingContext: rankingContext,
      );
    }

    // ─── SEMANTIC-ONLY (with optional object/date/camera/quality filters) ──
    return _searchSemanticOnly(
      parsedQuery,
      limit: limit,
      rankingContext: rankingContext,
    );
  }

  /// Object-only search: find photos containing specific YOLO-detected objects.
  /// Uses hard filtering on object_tags table, then ranks by object confidence.
  Future<List<RankedSearchResult>> _searchObjectOnly(
    ParsedQuery parsedQuery, {
    int limit = 20,
    RankingContext? rankingContext,
  }) async {
    final objectTags = parsedQuery.filters.objectTags;
    final excludeTags = parsedQuery.filters.excludeTags;

    // 1. Find photos with matching object tags
    final objectMatches = await database.objectTags.searchByLabels(objectTags);
    if (objectMatches.isEmpty && excludeTags.isEmpty) return [];

    // 2. Apply exclusion filter
    List<String> candidateIds;
    if (excludeTags.isNotEmpty) {
      final excluded = await database.objectTags.excludeLabels(
        excludeTags,
        requireAnyLabel: objectTags.isNotEmpty ? objectTags : null,
      );
      candidateIds = objectTags.isNotEmpty
          ? excluded.where((id) => objectMatches.containsKey(id)).toList()
          : excluded;
    } else {
      candidateIds = objectMatches.keys.toList();
    }

    if (candidateIds.isEmpty) return [];

    // 3. Batch fetch metadata
    final metadataMap = await database.photoMetadata.getByIds(candidateIds);
    // Batch favorites to avoid per-row query
    Set<String>? favoriteIds;
    if (parsedQuery.filters.favoritesOnly) {
      favoriteIds = await database.favorites.filterFavorites(candidateIds.toSet());
    }

    // 4. Build results with object confidence scores
    final results = <SearchResult>[];
    final objectSignals = <String, List<String>>{};
    for (final photoId in candidateIds) {
      final meta = metadataMap[photoId];
      if (meta == null) continue;
      if (!_matchesFiltersSync(meta, parsedQuery.filters, favoriteIds: favoriteIds)) continue;

      // Score is based on the highest object confidence for this photo
      final score = objectMatches[photoId] ?? 0.5;
      objectSignals[photoId] = ['object'];
      results.add(SearchResult(
        photoId: photoId,
        score: score,
        metadata: meta,
        objectScore: score,
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));

    // 5. Apply ranking engine — object intent boosts object relevance
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
      intent: SearchIntent.object,
    );

    return _withSignals(rankedResults, objectSignals).take(limit).toList();
  }

  /// Location-only search: find photos near a GPS coordinate.
  /// Uses bounding-box proximity search on photo_metadata lat/lng.
  Future<List<RankedSearchResult>> _searchLocationOnly(
    ParsedQuery parsedQuery, {
    int limit = 20,
    RankingContext? rankingContext,
  }) async {
    final locationLabel = parsedQuery.filters.locationLabel;

    // For now, location search requires GPS coordinates in metadata.
    // A future enhancement could add reverse geocoding (location label → lat/lng).
    // For now, search for photos that have any GPS data and use semantic matching
    // on the location label as a ranking signal.

    // Find photos with GPS data. Use pagination-friendly limit:
    // 500 covers most libraries in one page; caller can paginate via limit.
    // Hard cap 2000 prevents OOM but avoids silently missing results.
    final boundedLimit = (limit * 10).clamp(50, 2000);
    final rows = await database.database.rawQuery('''
      SELECT photo_id, latitude, longitude
      FROM photo_metadata
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL
      ORDER BY photo_id
      LIMIT ?
    ''', [boundedLimit]);

    if (rows.isEmpty) return [];

    final candidateIds = rows.map((r) => r['photo_id'] as String).toList();
    final metadataMap = await database.photoMetadata.getByIds(candidateIds);

    // If we have a location label, use semantic embedding to rank by location concept
    if (locationLabel != null && parsedQuery.semanticQuery.trim().isNotEmpty) {
      Float32List? queryEmbedding;
      Map<String, double> semanticScores = {};
      try {
        queryEmbedding = await embeddingProvider.generateTextEmbedding(
          parsedQuery.semanticQuery,
        );
        final candidates = await _getCandidateEmbeddings(parsedQuery.filters);
        semanticScores = _scoreCandidates(queryEmbedding, candidates).scores;
      } on StateError catch (e) {
        if (!e.message.contains('MODEL_NOT_READY')) rethrow;
        _logger.warning('Semantic unavailable for location ranking, using GPS only: $e');
      } catch (e) {
        _logger.warning('Semantic unavailable for location ranking (embedding init failed), using GPS only: $e');
      }

      // Batch favorites for this path
      Set<String>? favIds;
      if (parsedQuery.filters.favoritesOnly) {
        favIds = await database.favorites.filterFavorites(candidateIds.toSet());
      }
      final results = <SearchResult>[];
      for (final photoId in candidateIds) {
        final meta = metadataMap[photoId];
        if (meta == null) continue;
        if (!_matchesFiltersSync(meta, parsedQuery.filters, favoriteIds: favIds)) continue;

        // Base score: has GPS data
        double score = 0.5;

        // Boost if also matches semantic embedding (best row per photo)
        final semanticScore = semanticScores[photoId];
        if (semanticScore != null && queryEmbedding != null) {
          score = (score * 0.3) + (semanticScore * 0.7);
        }

        results.add(SearchResult(photoId: photoId, score: score, metadata: meta));
      }

      results.sort((a, b) => b.score.compareTo(a.score));

      final rankedResults = await rankingEngine.rank(
        results.take(limit * 3).toList(),
        context: rankingContext,
        intent: SearchIntent.location,
      );

      return rankedResults.take(limit).toList();
    }

    // No semantic query — just return photos with GPS data
    final favIds2 = parsedQuery.filters.favoritesOnly
        ? await database.favorites.filterFavorites(candidateIds.toSet())
        : null;
    final results = <SearchResult>[];
    for (final photoId in candidateIds) {
      final meta = metadataMap[photoId];
      if (meta == null) continue;
      if (!_matchesFiltersSync(meta, parsedQuery.filters, favoriteIds: favIds2)) continue;
      results.add(SearchResult(photoId: photoId, score: 0.5, metadata: meta));
    }

    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
      intent: SearchIntent.location,
    );

    return rankedResults.take(limit).toList();
  }

  /// Person + Semantic search: filter to person's photos, then rank by semantic similarity.
  /// This treats person membership as a hard constraint and semantic as a ranking signal.
  Future<List<RankedSearchResult>> _searchPersonWithSemantic(
    ParsedQuery parsedQuery, {
    int limit = 20,
    RankingContext? rankingContext,
  }) async {
    final personName = parsedQuery.filters.personName!;
    final semanticQuery = parsedQuery.semanticQuery;

    // 1. Resolve person to face photo IDs (fast DB lookup)
    final person = await database.peopleDao.getByDisplayName(personName);
    if (person == null) {
      _logger.info('No person found');
      return [];
    }

    final faces = await database.faces.getByPersonId(person.personId);
    if (faces.isEmpty) return [];

    final personPhotoIds = faces.map((f) => f.photoId).toSet();

    // 2. If object tags specified, intersect with person's photos
    Set<String>? objectPhotoIds;
    if (parsedQuery.filters.objectTags.isNotEmpty) {
      final objectMatches = await database.objectTags.searchByLabels(
        parsedQuery.filters.objectTags,
      );
      objectPhotoIds = objectMatches.keys.toSet();
      // Intersect: person ∩ objects
      final combined = personPhotoIds.intersection(objectPhotoIds);
      if (combined.isEmpty) return [];
      // Use combined set for further filtering
      personPhotoIds.clear();
      personPhotoIds.addAll(combined);
    }

    // 3. Generate semantic embedding for the query — fallback to person-only if text model missing
    Float32List? queryEmbedding;
    Map<String, double> personScores = {};
    try {
      queryEmbedding = await embeddingProvider.generateTextEmbedding(semanticQuery);
      final semanticCandidates = await _getCandidateEmbeddings(parsedQuery.filters);
      final scored = _scoreCandidates(queryEmbedding, semanticCandidates);
      for (final entry in scored.scores.entries) {
        if (personPhotoIds.contains(entry.key)) {
          personScores[entry.key] = entry.value;
        }
      }
    } catch (e) {
      if (e is StateError && !e.message.contains('MODEL_NOT_READY')) rethrow;
      _logger.warning('Semantic unavailable for person+semantic (embedding init failed), returning person-only: $e');
      // Fallback: return person's photos without semantic ranking
      final photoIds = personPhotoIds.toList();
      final metaMap = await database.photoMetadata.getByIds(photoIds);
      final favIds = parsedQuery.filters.favoritesOnly
          ? await database.favorites.filterFavorites(photoIds.toSet())
          : null;
      final fallback = <SearchResult>[];
      for (final pid in photoIds) {
        final meta = metaMap[pid];
        if (meta == null) continue;
        if (!_matchesFiltersSync(meta, parsedQuery.filters, favoriteIds: favIds)) continue;
        fallback.add(SearchResult(photoId: pid, score: 0.5, metadata: meta));
      }
      fallback.sort((a, b) => b.score.compareTo(a.score));
      final ranked = await rankingEngine.rank(fallback.take(limit * 3).toList(), context: rankingContext, intent: SearchIntent.person);
      return ranked.take(limit).toList();
    }

    // Batch fetch metadata (fix N+1)
    final candidateIds = personScores.keys.toList();
    final metadataMap = await database.photoMetadata.getByIds(candidateIds);
    final favIdsPerson = parsedQuery.filters.favoritesOnly
        ? await database.favorites.filterFavorites(candidateIds.toSet())
        : null;

    final results = <SearchResult>[];
    final personSignals = <String, List<String>>{};
    for (final photoId in candidateIds) {
      final score = personScores[photoId]!;

      // Apply metadata filters (date, camera, quality, etc.)
      final meta = metadataMap[photoId];
      if (meta != null) {
        if (!_matchesFiltersSync(meta, parsedQuery.filters, favoriteIds: favIdsPerson)) continue;
      } else if (parsedQuery.filters.hasLocation ||
          parsedQuery.filters.favoritesOnly) {
        continue;
      }

      personSignals[photoId] = ['person', 'semantic'];
      results.add(
        SearchResult(photoId: photoId, score: score, metadata: meta),
      );
    }

    // 5. Sort by semantic score
    results.sort((a, b) => b.score.compareTo(a.score));

    // 6. Apply ranking engine — person intent
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
      intent: SearchIntent.person,
    );

    return _withSignals(rankedResults, personSignals).take(limit).toList();
  }

  /// Semantic-only search (with optional object/date/camera/quality/location filters).
  /// Existing hybrid semantic + OCR path preserved. Object tags used as hard filter when present.
  Future<List<RankedSearchResult>> _searchSemanticOnly(
    ParsedQuery parsedQuery, {
    int limit = 20,
    RankingContext? rankingContext,
  }) async {
    final semanticQuery = parsedQuery.semanticQuery;
    final filters = parsedQuery.filters;

    // If object tags specified, use them as a hard filter
    Set<String>? objectPhotoIds;
    Map<String, double>? objectMatchScores;
    if (filters.objectTags.isNotEmpty) {
      final objectMatches = await database.objectTags.searchByLabels(
        filters.objectTags,
      );
      objectPhotoIds = objectMatches.keys.toSet();
      objectMatchScores = objectMatches;
      if (objectPhotoIds.isEmpty) return [];
    }

    // Generate text embedding for query — gracefully handle MODEL_NOT_READY
    Float32List? queryEmbedding;
    final Map<String, double> semanticScores = {};
    final Map<String, String> regionHits = {};
    bool semanticAvailable = true;
    final semanticTokens = semanticQuery
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet();
    try {
      queryEmbedding = await embeddingProvider.generateTextEmbedding(semanticQuery);
      final candidates = await _getCandidateEmbeddings(filters);
      final filteredCandidates = objectPhotoIds != null
          ? candidates.where((c) => objectPhotoIds!.contains(c.photoId)).toList()
          : candidates;
      final scored = _scoreCandidates(
        queryEmbedding,
        filteredCandidates,
        queryTokens: semanticTokens,
      );
      semanticScores.addAll(scored.scores);
      regionHits.addAll(scored.regionHits);
    } catch (e) {
      if (e is StateError && !e.message.contains('MODEL_NOT_READY')) rethrow;
      _logger.warning('Semantic unavailable (embedding init failed), using OCR-only: $e');
      semanticAvailable = false;
      // If no OCR will match either and no object filter, throw MODEL_NOT_READY
      // so UI shows install prompt rather than empty results.
      if (objectPhotoIds == null) {
        // Check if OCR has any chance — delay decision until OCR fetched
      }
    }
    // If semantic unavailable and no object filter, OCR-only search continues below

    // When falling back to OCR-only, use the ORIGINAL user query: the parser
    // expands semanticQuery with scene/object terms (e.g. "beach" becomes
    // "beach mountain forest ..."), which can never substring-match OCR text
    // via LIKE '%query%'. The raw query ("beach") matches correctly.
    final ocrQuery = (!semanticAvailable &&
            (parsedQuery.originalQuery?.trim().isNotEmpty ?? false))
        ? parsedQuery.originalQuery!.trim()
        : semanticQuery;

    // Get OCR text matches
    final ocrRecords = await database.ocrResults.searchOcrText(ocrQuery);
    final Map<String, double> ocrTextScoreMap = {};
    final queryTokens = ocrQuery
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    for (final record in ocrRecords) {
      // If object filtering active, skip OCR results not in object set
      if (objectPhotoIds != null && !objectPhotoIds.contains(record.photoId)) {
        continue;
      }
      final textLower = record.text.toLowerCase();
      double relevance;
      if (queryTokens.isEmpty) {
        relevance = textLower.contains(ocrQuery.toLowerCase()) ? 1.0 : 0.0;
      } else {
        final matched = queryTokens.where(textLower.contains).length;
        relevance = matched / queryTokens.length;
      }
      final score = relevance * record.confidence.clamp(0.0, 1.0);
      final current = ocrTextScoreMap[record.photoId];
      if (current == null || score > current) {
        ocrTextScoreMap[record.photoId] = score;
      }
    }

    // Combine candidates from both sources
    final Set<String> allCandidateIds = <String>{};
    allCandidateIds.addAll(semanticScores.keys);
    allCandidateIds.addAll(ocrTextScoreMap.keys);

    // Exclusions ("without X") when no object hard-filter is active: drop
    // photos containing any excluded label. Computed directly (not via
    // excludeLabels) so photos with zero detections are kept.
    Set<String>? excludedIds;
    if (filters.excludeTags.isNotEmpty && objectPhotoIds == null) {
      excludedIds = await _excludedPhotoIds(filters.excludeTags);
      allCandidateIds.removeAll(excludedIds);
    }

    // Build results with batch metadata query (fix N+1)
    final candidateList = allCandidateIds.toList();
    final metadataMap = await database.photoMetadata.getByIds(candidateList);
    final favIdsSemantic = filters.favoritesOnly
        ? await database.favorites.filterFavorites(allCandidateIds)
        : null;

    const double semanticWeight = 0.7;
    const double textWeight = 0.3;

    final results = <SearchResult>[];
    final semanticSignals = <String, List<String>>{};
    for (final photoId in candidateList) {
      final meta = metadataMap[photoId];
      if (meta == null) continue;

      if (!_matchesFiltersSync(meta, filters, favoriteIds: favIdsSemantic)) continue;

      final semanticScore = semanticScores[photoId] ?? 0.0;
      final textMatchScore = ocrTextScoreMap[photoId] ?? 0.0;

      final double combinedScore =
          (semanticScore * semanticWeight) + (textMatchScore * textWeight);

      final signals = <String>[];
      if (textMatchScore > 0) signals.add('ocr');
      if (semanticScore >= 0.25) signals.add('semantic');
      if ((objectMatchScores?[photoId] ?? 0) > 0) signals.add('object');
      final regionLabel = regionHits[photoId];
      if (regionLabel != null) signals.add('region:$regionLabel');
      if (signals.isNotEmpty) semanticSignals[photoId] = signals;

      results.add(
        SearchResult(
          photoId: photoId,
          score: combinedScore,
          metadata: meta,
          objectScore: objectMatchScores?[photoId],
        ),
      );
    }

    // Sort by combined score
    results.sort((a, b) => b.score.compareTo(a.score));

    // Apply ranking engine — use parsed intent for weighting
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
      intent: parsedQuery.intent,
    );

    return _withSignals(rankedResults, semanticSignals).take(limit).toList();
  }

  /// Search by image (reverse image search).
  Future<List<RankedSearchResult>> searchByImage(
    Uint8List imageBytes, {
    int limit = 20,
    SearchFilters? filters,
    RankingContext? rankingContext,
  }) async {
    _logger.info('Reverse image search');

    late final Float32List queryEmbedding;
    try {
      queryEmbedding = await embeddingProvider.generateEmbedding(imageBytes);
    } on StateError catch (e) {
      if (e.message.contains('MODEL_NOT_READY')) {
        _logger.warning('Image search unavailable: $e');
        throw StateError('MODEL_NOT_READY: Vision model not available — please download embedding model from Settings > AI Models');
      }
      rethrow;
    } catch (e) {
      _logger.warning('Image search unavailable (embedding init failed): $e');
      throw StateError('MODEL_NOT_READY: Vision model not available — please download embedding model from Settings > AI Models');
    }

    final candidates = await _getCandidateEmbeddings(filters);
    final scored = _scoreCandidates(queryEmbedding, candidates);

    // Batch fetch metadata (fix N+1)
    final candidateIds = scored.scores.keys.toList();
    final metadataMap = await database.photoMetadata.getByIds(candidateIds);
    Set<String>? favIdsImg;
    if (filters?.favoritesOnly == true) {
      favIdsImg = await database.favorites.filterFavorites(candidateIds.toSet());
    }

    final results = <SearchResult>[];
    final imageSignals = <String, List<String>>{};
    for (final entry in scored.scores.entries) {
      final meta = metadataMap[entry.key];
      if (meta == null) continue;
      if (filters != null && !_matchesFiltersSync(meta, filters, favoriteIds: favIdsImg)) continue;
      if (entry.value >= 0.25) imageSignals[entry.key] = ['semantic'];
      results.add(
        SearchResult(photoId: entry.key, score: entry.value, metadata: meta),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));

    // Apply ranking engine — image search is scene-like
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
      intent: SearchIntent.scene,
    );

    return _withSignals(rankedResults, imageSignals).take(limit).toList();
  }

  /// Search for photos containing a specific person by name.
  ///
  /// Finds all faces assigned to the person, then returns the associated photos.
  /// Optionally combines with other filters.
  Future<List<RankedSearchResult>> searchByPerson(
    String personName, {
    int limit = 50,
    SearchFilters? filters,
    RankingContext? rankingContext,
  }) async {
    _logger.info('Searching for person');

    // Find person by name (case-insensitive)
    final person = await database.peopleDao.getByDisplayName(personName);
    if (person == null) {
      _logger.info('No person found');
      return [];
    }

    // Get all face photo IDs for this person
    final faces = await database.faces.getByPersonId(person.personId);
    if (faces.isEmpty) return [];

    final photoIds = faces.map((f) => f.photoId).toSet().toList();

    // Batch fetch metadata (fix N+1)
    final metadataMap = await database.photoMetadata.getByIds(photoIds);
    Set<String>? favIdsPerson2;
    if (filters?.favoritesOnly == true) {
      favIdsPerson2 = await database.favorites.filterFavorites(photoIds.toSet());
    }

    // Build results
    final results = <SearchResult>[];
    for (final photoId in photoIds) {
      final meta = metadataMap[photoId];
      if (meta == null) continue;
      if (filters != null && !_matchesFiltersSync(meta, filters, favoriteIds: favIdsPerson2)) continue;

      results.add(
        SearchResult(photoId: photoId, score: 1.0, metadata: meta),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));

    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
      intent: SearchIntent.person,
    );

    final personOnlySignals = {
      for (final r in rankedResults) r.photoId: const ['person'],
    };
    return _withSignals(rankedResults, personOnlySignals).take(limit).toList();
  }

  /// Search for similar photos to a given photo ID.
  Future<List<RankedSearchResult>> searchSimilar(
    String photoId, {
    int limit = 20,
    SearchFilters? filters,
    RankingContext? rankingContext,
  }) async {
    final queryEmbedding = await _getEmbedding(photoId);
    if (queryEmbedding == null) {
      _logger.warning('No embedding found for photo: $photoId');
      return [];
    }

    final candidates = await _getCandidateEmbeddings(filters);
    final scored = _scoreCandidates(queryEmbedding, candidates);

    // Batch fetch metadata (fix N+1)
    final candidateIds = scored.scores.keys.toList();
    final metadataMap = await database.photoMetadata.getByIds(candidateIds);
    Set<String>? favIdsSimilar;
    if (filters?.favoritesOnly == true) {
      favIdsSimilar = await database.favorites.filterFavorites(candidateIds.toSet());
    }

    final results = <SearchResult>[];
    for (final entry in scored.scores.entries) {
      if (entry.key == photoId) continue; // Skip self
      final meta = metadataMap[entry.key];
      if (meta == null) continue;
      if (filters != null && !_matchesFiltersSync(meta, filters, favoriteIds: favIdsSimilar)) continue;
      results.add(
        SearchResult(photoId: entry.key, score: entry.value, metadata: meta),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));

    // Apply ranking engine — similar photos are scene-like
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
      intent: SearchIntent.scene,
    );

    return rankedResults.take(limit).toList();
  }

  /// Get all embeddings matching filters (with caching).
  ///
  /// Returns one row per stored embedding: the whole-photo (global) row plus
  /// any per-region (object crop) rows. Callers collapse to per-photo scores
  /// via [_scoreCandidates], which keeps the best row per photo.
  Future<List<Embedding>> _getCandidateEmbeddings(
    SearchFilters? filters,
  ) async {
    // Get the active model ID to filter embeddings - only compare embeddings from the same model
    final activeModelId = _activeModelId;

    // If cache is populated and no complex filters, use cache (filtered by model)
    if (_embeddingCache.isNotEmpty &&
        (filters == null || !filters.hasActiveFilters)) {
      if (activeModelId.isNotEmpty && activeModelId != 'unknown') {
        return _embeddingCache.values
            .where((e) => e.model == activeModelId)
            .toList();
      }
      return _embeddingCache.values.toList();
    }

    // Otherwise fetch from database with filters
    final whereConditions = <String>[];
    final whereArgs = <Object>[];

    // CRITICAL: Filter by active model ID to prevent embedding-space mixing
    if (activeModelId.isNotEmpty && activeModelId != 'unknown') {
      whereConditions.add('e.model = ?');
      whereArgs.add(activeModelId);
    }

    if (filters?.dateFrom != null) {
      whereConditions.add('pm.date_created >= ?');
      whereArgs.add(filters!.dateFrom!.toIso8601String());
    }
    if (filters?.dateTo != null) {
      whereConditions.add('pm.date_created <= ?');
      whereArgs.add(filters!.dateTo!.toIso8601String());
    }
    if (filters?.minQualityScore != null) {
      whereConditions.add('pm.quality_score >= ?');
      whereArgs.add(filters!.minQualityScore!);
    }
    if (filters?.maxBlurScore != null) {
      whereConditions.add('pm.blur_score <= ?');
      whereArgs.add(filters!.maxBlurScore!);
    }
    if (filters?.hasLocation == true) {
      whereConditions.add(
        'pm.latitude IS NOT NULL AND pm.longitude IS NOT NULL',
      );
    }
    if (filters?.cameraMake != null) {
      whereConditions.add('pm.camera_make = ?');
      whereArgs.add(filters!.cameraMake!);
    }
    if (filters?.cameraModel != null) {
      whereConditions.add('pm.camera_model = ?');
      whereArgs.add(filters!.cameraModel!);
    }
    if (filters?.albumId != null) {
      whereConditions.add('pm.album_id = ?');
      whereArgs.add(filters!.albumId!);
    }
    if (filters?.folderPath != null) {
      whereConditions.add('pm.folder_path = ?');
      whereArgs.add(filters!.folderPath!);
    }
    if (filters?.mediaType != null) {
      whereConditions.add('pm.media_type = ?');
      whereArgs.add(filters!.mediaType!);
    }
    if (filters?.orientation != null) {
      whereConditions.add('pm.orientation = ?');
      whereArgs.add(filters!.orientation!);
    }
    if (filters?.minWidth != null) {
      whereConditions.add('pm.width >= ?');
      whereArgs.add(filters!.minWidth!);
    }
    if (filters?.maxWidth != null) {
      whereConditions.add('pm.width <= ?');
      whereArgs.add(filters!.maxWidth!);
    }
    if (filters?.minHeight != null) {
      whereConditions.add('pm.height >= ?');
      whereArgs.add(filters!.minHeight!);
    }
    if (filters?.maxHeight != null) {
      whereConditions.add('pm.height <= ?');
      whereArgs.add(filters!.maxHeight!);
    }

    // Handle favoritesOnly filter - need to join with favorites table
    String favoritesJoin = '';
    if (filters?.favoritesOnly == true) {
      favoritesJoin = 'INNER JOIN favorites f ON e.photo_id = f.asset_id';
    }

    // Handle personName filter - need to join with faces table
    String personJoin = '';
    if (filters?.personName != null) {
      personJoin = '''
        INNER JOIN faces fc ON e.photo_id = fc.photo_id
        INNER JOIN people pp ON fc.person_id = pp.person_id
          AND pp.status = 'active'
      ''';
      whereConditions.add('LOWER(pp.display_name) = LOWER(?)');
      whereArgs.add(filters!.personName!);
    }

    final whereClause = whereConditions.isEmpty
        ? ''
        : 'WHERE ${whereConditions.join(' AND ')}';

    final rows = await database.database.rawQuery('''
      SELECT e.id, e.photo_id, e.model, e.vector, e.created_at, e.region_label
      FROM embeddings e
      LEFT JOIN photo_metadata pm ON e.photo_id = pm.photo_id
      $favoritesJoin
      $personJoin
      $whereClause
    ''', whereArgs);

    final embeddings = <Embedding>[];
    for (final row in rows) {
      final vector = _blobToFloat32List(row['vector'] as List<int>);
      final rowId = row['id'] as String? ?? row['photo_id'] as String;
      final embedding = Embedding(
        id: rowId,
        photoId: row['photo_id'] as String,
        model: row['model'] as String,
        vector: vector,
        createdAt: DateTime.parse(row['created_at'] as String),
        regionLabel: row['region_label'] as String?,
      );
      embeddings.add(embedding);

      // Update cache, evicting stale-model entries if at capacity
      if (_embeddingCache.length >= _maxCacheSize) {
        // Purge entries from a different model to make room
        purgeStaleModelEntries();
      }
      if (_embeddingCache.length < _maxCacheSize) {
        _embeddingCache[rowId] = embedding;
      }
    }

    return embeddings;
  }

  /// Score candidate rows against [queryEmbedding], collapsing to the best
  /// score per photo.
  ///
  /// A photo may have several rows (one global + N region rows). The photo's
  /// score is the max over its rows. When the winning row is a region whose
  /// label appears in [queryTokens], a small bonus is applied and the label
  /// is recorded in [regionHits] — this is what lets small/background objects
  /// in complex scenes outrank photos where the concept merely dominates.
  ({Map<String, double> scores, Map<String, String> regionHits})
      _scoreCandidates(
    Float32List queryEmbedding,
    List<Embedding> candidates, {
    Set<String> queryTokens = const {},
  }) {
    final scores = <String, double>{};
    final regionHits = <String, String>{};
    for (final candidate in candidates) {
      var score = _cosineSimilarity(queryEmbedding, candidate.vector);
      final label = candidate.regionLabel;
      if (label != null && _labelMatchesTokens(label, queryTokens)) {
        score = (score + _regionMatchBonus).clamp(0.0, 1.0);
      }
      final current = scores[candidate.photoId];
      if (current == null || score > current) {
        scores[candidate.photoId] = score;
        if (label != null && _labelMatchesTokens(label, queryTokens)) {
          regionHits[candidate.photoId] = label;
        } else {
          regionHits.remove(candidate.photoId);
        }
      }
    }
    return (scores: scores, regionHits: regionHits);
  }

  /// Bonus applied when a region row's label matches the query.
  static const double _regionMatchBonus = 0.05;

  /// Whether a region [label] (e.g. "dining table") is referenced by the
  /// query tokens, tolerating simple plurals.
  bool _labelMatchesTokens(String label, Set<String> queryTokens) {
    if (queryTokens.isEmpty) return false;
    final words = label.toLowerCase().split(' ');
    return words.every(
      (w) => queryTokens.contains(w) || queryTokens.contains('${w}s'),
    );
  }

  /// Attach per-photo match signals to ranked results (powers the "why this
  /// matched" UI). Photos without recorded signals keep empty signals.
  List<RankedSearchResult> _withSignals(
    List<RankedSearchResult> ranked,
    Map<String, List<String>> signals,
  ) {
    return ranked
        .map((r) => signals.containsKey(r.photoId)
            ? r.copyWith(matchedSignals: signals[r.photoId]!)
            : r)
        .toList();
  }

  /// Photo IDs containing any of [labels] (confidence >= 0.3), used to enforce
  /// "without X" exclusions without dropping photos that have no detections.
  Future<Set<String>> _excludedPhotoIds(List<String> labels) async {
    if (labels.isEmpty) return {};
    final placeholders = labels.map((_) => '?').join(',');
    final rows = await database.database.rawQuery(
      'SELECT DISTINCT photo_id FROM object_tags '
      'WHERE label IN ($placeholders) AND confidence >= ?',
      [...labels, 0.3],
    );
    return rows.map((r) => r['photo_id'] as String).toSet();
  }

  /// Get a single embedding by photo ID.
  Future<Float32List?> _getEmbedding(String photoId) async {
    // Check cache first
    if (_embeddingCache.containsKey(photoId)) {
      final cached = _embeddingCache[photoId]!;
      // Verify model matches
      if (cached.model == _activeModelId) {
        return cached.vector;
      }
    }

    // Fetch from database with model filter
    final activeModelId = _activeModelId;
    String whereClause = 'photo_id = ?';
    List<Object> whereArgs = [photoId];

    if (activeModelId.isNotEmpty && activeModelId != 'unknown') {
      whereClause += ' AND model = ?';
      whereArgs.add(activeModelId);
    }

    final row = await database.database.query(
      'embeddings',
      where: whereClause,
      whereArgs: whereArgs,
      // Prefer the whole-photo (global) row over region rows
      orderBy: 'region_label ASC',
      limit: 1,
    );

    if (row.isEmpty) return null;

    final vector = _blobToFloat32List(row.first['vector'] as List<int>);
    return vector;
  }

  /// Convert BLOB to Float32List.
  Float32List _blobToFloat32List(List<int> blob) {
    final byteData = ByteData(blob.length);
    for (int i = 0; i < blob.length; i++) {
      byteData.setUint8(i, blob[i]);
    }
    final float32 = Float32List(byteData.lengthInBytes ~/ 4);
    for (int i = 0; i < float32.length; i++) {
      float32[i] = byteData.getFloat32(i * 4, Endian.little);
    }
    return float32;
  }

  /// Cosine similarity between two vectors.
  double _cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) return 0.0;

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA <= 0 || normB <= 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// Clear the embedding cache.
  void clearCache() {
    _embeddingCache.clear();
    _cachedModelId = null;
  }

  /// Purge embeddings from the cache that belong to a different model.
  /// Call this when the active model changes to avoid stale vectors.
  void purgeStaleModelEntries() {
    final activeId = _activeModelId;
    if (activeId.isEmpty || activeId == 'unknown') return;
    final before = _embeddingCache.length;
    _embeddingCache.removeWhere((_, e) => e.model != activeId);
    final removed = before - _embeddingCache.length;
    if (removed > 0) {
      _logger.info('Purged $removed stale-model embeddings from cache');
    }
    _cachedModelId = activeId;
  }

  /// Preload embeddings into cache (call on app startup or after indexing).
  /// Respects [_maxCacheSize] and purges stale-model entries first.
  Future<void> preloadCache({int limit = 5000}) async {
    _logger.info('Preloading embedding cache for model: $_activeModelId');

    // If model changed since last preload, clear stale entries
    if (_cachedModelId != null && _cachedModelId != _activeModelId) {
      _logger.info('Model changed ($_cachedModelId -> $_activeModelId), clearing cache');
      clearCache();
    }

    final effectiveLimit = limit.clamp(0, _maxCacheSize);
    final activeModelId = _activeModelId;

    String whereClause = '';
    List<Object> whereArgs = [];

    if (activeModelId.isNotEmpty && activeModelId != 'unknown') {
      whereClause = 'WHERE model = ?';
      whereArgs = [activeModelId];
    }

    final rows = await database.database.rawQuery(
      '''
      SELECT photo_id, model, vector, created_at
      FROM embeddings
      $whereClause
      LIMIT ?
    ''',
      [...whereArgs, effectiveLimit],
    );

    for (final row in rows) {
      if (_embeddingCache.length >= _maxCacheSize) break;
      final vector = _blobToFloat32List(row['vector'] as List<int>);
      _embeddingCache[row['photo_id'] as String] = Embedding(
        id: row['photo_id'] as String,
        photoId: row['photo_id'] as String,
        model: row['model'] as String,
        vector: vector,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }
    _cachedModelId = activeModelId;

    _logger.info(
      'Cached ${_embeddingCache.length} embeddings for model $_activeModelId',
    );
  }

  /// Search video segments by label, OCR text, or person name.
  /// Returns matching SearchResult with videoSegmentTimestampMs set.
  Future<List<SearchResult>> searchVideoSegments({
    String? query,
    String? label,
    String? personId,
    int limit = 20,
  }) async {
    final results = <SearchResult>[];

    try {
      final whereConditions = <String>[];
      final whereArgs = <Object>[];

      if (label != null) {
        whereConditions.add('labels LIKE ?');
        whereArgs.add('%$label%');
      }
      if (personId != null) {
        whereConditions.add('people LIKE ?');
        whereArgs.add('%$personId%');
      }
      if (query != null && query.isNotEmpty) {
        whereConditions.add('(ocr_text LIKE ? OR labels LIKE ?)');
        whereArgs.addAll(['%$query%', '%$query%']);
      }

      if (whereConditions.isEmpty) return results;

      final whereClause = whereConditions.join(' AND ');
      final rows = await database.database.rawQuery(
        'SELECT video_id, start_time_ms, confidence '
        'FROM video_segments '
        'WHERE $whereClause '
        'ORDER BY confidence DESC '
        'LIMIT ?',
        [...whereArgs, limit],
      );

      for (final row in rows) {
        results.add(SearchResult(
          photoId: row['video_id'] as String,
          score: (row['confidence'] as double?) ?? 0.5,
          videoSegmentTimestampMs: row['start_time_ms'] as int,
        ));
      }
    } catch (e) {
      _logger.warning('Video segment search failed', error: e);
    }

    return results;
  }

  /// Search video segments within a specific time range.
  ///
  /// Useful for "what happened at 2:30 in the vacation video?" queries.
  Future<List<SearchResult>> searchVideoByTimeRange({
    required String videoId,
    required int startMs,
    required int endMs,
    int limit = 10,
  }) async {
    final results = <SearchResult>[];
    try {
      final rows = await database.database.rawQuery(
        'SELECT video_id, start_time_ms, end_time_ms, confidence, '
        'labels, people, ocr_text '
        'FROM video_segments '
        'WHERE video_id = ? '
        'AND start_time_ms < ? AND end_time_ms > ? '
        'ORDER BY confidence DESC '
        'LIMIT ?',
        [videoId, endMs, startMs, limit],
      );

      for (final row in rows) {
        results.add(SearchResult(
          photoId: row['video_id'] as String,
          score: (row['confidence'] as double?) ?? 0.5,
          videoSegmentTimestampMs: row['start_time_ms'] as int,
        ));
      }
    } catch (e) {
      _logger.warning('Video time range search failed', error: e);
    }
    return results;
  }

  /// Get all unique people detected across all videos.
  Future<List<String>> getVideoPeople() async {
    try {
      final rows = await database.database.rawQuery(
        'SELECT DISTINCT people FROM video_segments '
        'WHERE people IS NOT NULL AND people != \'\'',
      );
      final people = <String>{};
      for (final row in rows) {
        final peopleStr = row['people'] as String? ?? '';
        for (final p in peopleStr.split(',')) {
          final trimmed = p.trim();
          if (trimmed.isNotEmpty && !trimmed.startsWith('face:')) {
            people.add(trimmed);
          }
        }
      }
      return people.toList()..sort();
    } catch (e) {
      _logger.warning('Failed to get video people', error: e);
      return [];
    }
  }

  /// Get all unique object labels detected across all videos.
  Future<List<String>> getVideoObjectLabels() async {
    try {
      final rows = await database.database.rawQuery(
        'SELECT DISTINCT labels FROM video_segments '
        'WHERE labels IS NOT NULL AND labels != \'\'',
      );
      final labels = <String>{};
      for (final row in rows) {
        final labelsStr = row['labels'] as String? ?? '';
        for (final l in labelsStr.split(',')) {
          final trimmed = l.trim();
          if (trimmed.isNotEmpty) labels.add(trimmed);
        }
      }
      return labels.toList()..sort();
    } catch (e) {
      _logger.warning('Failed to get video object labels', error: e);
      return [];
    }
  }
}
