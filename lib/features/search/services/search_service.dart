import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/embedding.dart';
import '../../../domain/models/photo_metadata.dart';
import '../../../ai/providers/embedding_provider.dart';
import 'natural_language_parser.dart';
import 'ranking_engine.dart';
import 'search_suggestion_service.dart';

/// Result of a search query.
class SearchResult {
  const SearchResult({
    required this.photoId,
    required this.score,
    this.metadata,
    this.thumbnailUrl,
  });

  final String photoId;
  final double score;
  final PhotoMetadata? metadata;
  final String? thumbnailUrl;
}

/// Search filters for refining results.
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

  SearchFilters copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    double? minQualityScore,
    double? maxBlurScore,
    bool? hasLocation,
    String? cameraMake,
    String? cameraModel,
    String? albumId,
    String? folderPath,
    String? mediaType,
    int? orientation,
    bool? favoritesOnly,
    int? minWidth,
    int? maxWidth,
    int? minHeight,
    int? maxHeight,
  }) {
    return SearchFilters(
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      minQualityScore: minQualityScore ?? this.minQualityScore,
      maxBlurScore: maxBlurScore ?? this.maxBlurScore,
      hasLocation: hasLocation ?? this.hasLocation,
      cameraMake: cameraMake ?? this.cameraMake,
      cameraModel: cameraModel ?? this.cameraModel,
      albumId: albumId ?? this.albumId,
      folderPath: folderPath ?? this.folderPath,
      mediaType: mediaType ?? this.mediaType,
      orientation: orientation ?? this.orientation,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      minWidth: minWidth ?? this.minWidth,
      maxWidth: maxWidth ?? this.maxWidth,
      minHeight: minHeight ?? this.minHeight,
      maxHeight: maxHeight ?? this.maxHeight,
    );
  }

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
      maxHeight != null;
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

  /// Maximum embeddings to cache in memory.
  static const _maxCacheSize = 10000;

  /// Performs a text-based semantic search with ranking.
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

    _logger.info('Searching for: "$query"');

    // Record search suggestion
    if (recordSuggestion) {
      unawaited(suggestionService.recordSearch(query));
    }

    // Generate text embedding for query
    final queryEmbedding = await provider.generateTextEmbedding(query);

    // Get candidate embeddings (from cache or database)
    final candidates = await _getCandidateEmbeddings(filters);

    // Compute cosine similarity
    final results = <SearchResult>[];
    for (final candidate in candidates) {
      final score = _cosineSimilarity(queryEmbedding, candidate.vector);

      // Apply filter thresholds using metadata
      final meta = await database.photoMetadata.getById(candidate.photoId);
      if (meta != null) {
        if (filters != null && !_matchesFilters(meta, filters)) continue;
      } else if (filters?.hasLocation == true || filters?.favoritesOnly == true) {
        // No metadata - skip if location or favorites required
        continue;
      }

      results.add(SearchResult(
        photoId: candidate.photoId,
        score: score,
        metadata: meta,
      ));
    }

    // Sort by score descending
    results.sort((a, b) => b.score.compareTo(a.score));

    // Apply ranking engine
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(), // Get more candidates for ranking
      context: rankingContext,
    );

    // Apply limit after ranking
    return rankedResults.take(limit).toList();
  }

  /// Checks if metadata matches all active filters.
  bool _matchesFilters(PhotoMetadata meta, SearchFilters filters) {
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
    if (filters.cameraMake != null &&
        meta.cameraMake != filters.cameraMake) {
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
    if (filters.orientation != null && meta.orientation != filters.orientation) {
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
    return true;
  }

  /// Performs a search using a pre-parsed natural language query.
  ///
  /// This method uses the semantic query from the parsed result for vector search
  /// and applies the extracted filters as hard constraints.
  Future<List<RankedSearchResult>> searchParsed(
    ParsedQuery parsedQuery, {
    int limit = 20,
    RankingContext? rankingContext,
    bool recordSuggestion = true,
  }) async {
    if (parsedQuery.semanticQuery.trim().isEmpty) return [];

    _logger.info('Searching with parsed query: "${parsedQuery.semanticQuery}"'
        ' (filters: ${parsedQuery.confidence})');

    // Record search suggestion
    if (recordSuggestion) {
      unawaited(suggestionService.recordSearch(parsedQuery.originalQuery ?? parsedQuery.semanticQuery));
    }

    // Use the semantic query for embedding generation
    final queryEmbedding = await embeddingProvider.generateTextEmbedding(parsedQuery.semanticQuery);

    // Get candidate embeddings with filters applied
    final candidates = await _getCandidateEmbeddings(parsedQuery.filters);

    // Compute cosine similarity and apply metadata filters
    final results = <SearchResult>[];
    for (final candidate in candidates) {
      final score = _cosineSimilarity(queryEmbedding, candidate.vector);

      // Apply filter thresholds using metadata (redundant with _getCandidateEmbeddings but safe)
      final meta = await database.photoMetadata.getById(candidate.photoId);
      if (meta != null) {
        if (!_matchesFilters(meta, parsedQuery.filters)) continue;
      } else if (parsedQuery.filters.hasLocation == true || parsedQuery.filters.favoritesOnly == true) {
        continue;
      }

      results.add(SearchResult(
        photoId: candidate.photoId,
        score: score,
        metadata: meta,
      ));
    }

    // Sort by score descending
    results.sort((a, b) => b.score.compareTo(a.score));

    // Apply ranking engine
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
    );

    // Apply limit after ranking
    return rankedResults.take(limit).toList();
  }

  /// Search by image (reverse image search).
  Future<List<RankedSearchResult>> searchByImage(
    Uint8List imageBytes, {
    int limit = 20,
    SearchFilters? filters,
    RankingContext? rankingContext,
  }) async {
    _logger.info('Reverse image search');

    final queryEmbedding = await embeddingProvider.generateEmbedding(imageBytes);

    final candidates = await _getCandidateEmbeddings(filters);

    final results = <SearchResult>[];
    for (final candidate in candidates) {
      final score = _cosineSimilarity(queryEmbedding, candidate.vector);
      final meta = await database.photoMetadata.getById(candidate.photoId);
      if (meta != null && filters != null && !_matchesFilters(meta, filters)) continue;
      results.add(SearchResult(
        photoId: candidate.photoId,
        score: score,
        metadata: meta,
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));

    // Apply ranking engine
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
    );

    return rankedResults.take(limit).toList();
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

    final results = <SearchResult>[];
    for (final candidate in candidates) {
      if (candidate.photoId == photoId) continue; // Skip self
      final score = _cosineSimilarity(queryEmbedding, candidate.vector);
      final meta = await database.photoMetadata.getById(candidate.photoId);
      if (meta != null && filters != null && !_matchesFilters(meta, filters)) continue;
      results.add(SearchResult(
        photoId: candidate.photoId,
        score: score,
        metadata: meta,
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));

    // Apply ranking engine
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
    );

    return rankedResults.take(limit).toList();
  }

  /// Get all embeddings matching filters (with caching).
  Future<List<Embedding>> _getCandidateEmbeddings(SearchFilters? filters) async {
    // If cache is populated and no complex filters, use cache
    if (_embeddingCache.isNotEmpty &&
        (filters == null || !filters.hasActiveFilters)) {
      return _embeddingCache.values.toList();
    }

    // Otherwise fetch from database with filters
    final whereConditions = <String>[];
    final whereArgs = <Object>[];

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
      whereConditions.add('pm.latitude IS NOT NULL AND pm.longitude IS NOT NULL');
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

    final whereClause = whereConditions.isEmpty
        ? ''
        : 'WHERE ${whereConditions.join(' AND ')}';

    final rows = await database.database.rawQuery('''
      SELECT e.photo_id, e.model, e.vector, e.created_at
      FROM embeddings e
      LEFT JOIN photo_metadata pm ON e.photo_id = pm.photo_id
      $favoritesJoin
      $whereClause
    ''', whereArgs);

    final embeddings = <Embedding>[];
    for (final row in rows) {
      final vector = _blobToFloat32List(row['vector'] as List<int>);
      final embedding = Embedding(
        id: row['photo_id'] as String,
        photoId: row['photo_id'] as String,
        model: row['model'] as String,
        vector: vector,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
      embeddings.add(embedding);

      // Update cache
      if (_embeddingCache.length < _maxCacheSize) {
        _embeddingCache[row['photo_id'] as String] = embedding;
      }
    }

    return embeddings;
  }

  /// Get a single embedding by photo ID.
  Future<Float32List?> _getEmbedding(String photoId) async {
    // Check cache first
    if (_embeddingCache.containsKey(photoId)) {
      return _embeddingCache[photoId]!.vector;
    }

    // Fetch from database
    final row = await database.database.query(
      'embeddings',
      where: 'photo_id = ?',
      whereArgs: [photoId],
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
  }

  /// Preload embeddings into cache (call on app startup or after indexing).
  Future<void> preloadCache({int limit = 5000}) async {
    _logger.info('Preloading embedding cache...');
    final rows = await database.database.query(
      'embeddings',
      columns: ['photo_id', 'model', 'vector', 'created_at'],
      limit: limit,
    );

    for (final row in rows) {
      final vector = _blobToFloat32List(row['vector'] as List<int>);
      _embeddingCache[row['photo_id'] as String] = Embedding(
        id: row['photo_id'] as String,
        photoId: row['photo_id'] as String,
        model: row['model'] as String,
        vector: vector,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }

    _logger.info('Cached ${_embeddingCache.length} embeddings');
  }
}