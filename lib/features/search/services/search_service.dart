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
    this.personName,
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
      personName != null;
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

    _logger.info('Searching for: "$query"');

    // Record search suggestion
    if (recordSuggestion) {
      unawaited(suggestionService.recordSearch(query));
    }

    // Generate text embedding for query (semantic search)
    final queryEmbedding = await provider.generateTextEmbedding(query);

    // Get candidate embeddings (from cache or database) for semantic search
    final semanticCandidates = await _getCandidateEmbeddings(filters);

    // Compute semantic similarity scores
    final Map<String, double> semanticScores = {};
    for (final candidate in semanticCandidates) {
      final score = _cosineSimilarity(queryEmbedding, candidate.vector);
      semanticScores[candidate.photoId] = score;
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

    // Build hybrid search results
    final results = <SearchResult>[];
    for (final photoId in allCandidateIds) {
      // Get metadata for filtering and result
      final meta = await database.photoMetadata.getById(photoId);
      if (meta == null) {
        // Skip if no metadata (should not happen for indexed photos, but safe)
        continue;
      }

      // Apply filters
      if (filters != null && !await _matchesFilters(meta, filters)) {
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
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(), // Get more candidates for ranking
      context: rankingContext,
    );

    // Apply limit after ranking
    return rankedResults.take(limit).toList();
  }

  /// Checks if metadata matches all active filters.
  Future<bool> _matchesFilters(
    PhotoMetadata meta,
    SearchFilters filters,
  ) async {
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
      final isFavorite = await database.favorites.isFavorite(meta.photoId);
      if (!isFavorite) {
        return false;
      }
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
    final hasSemanticQuery = parsedQuery.semanticQuery.trim().isNotEmpty;
    final hasPersonFilter = parsedQuery.filters.personName != null;

    if (!hasSemanticQuery && !hasPersonFilter) return [];

    _logger.info(
      'Searching with parsed query: "${parsedQuery.semanticQuery}"'
      ' (filters: ${parsedQuery.confidence})',
    );

    // Record search suggestion
    if (recordSuggestion) {
      unawaited(
        suggestionService.recordSearch(
          parsedQuery.originalQuery ?? parsedQuery.semanticQuery,
        ),
      );
    }

    // If only person filter (no semantic query), use person-only search
    if (!hasSemanticQuery && hasPersonFilter) {
      return searchByPerson(
        parsedQuery.filters.personName!,
        limit: limit,
        filters: parsedQuery.filters,
        rankingContext: rankingContext,
      );
    }

    // Use the semantic query for embedding generation
    final queryEmbedding = await embeddingProvider.generateTextEmbedding(
      parsedQuery.semanticQuery,
    );

    // Get candidate embeddings with filters applied
    final candidates = await _getCandidateEmbeddings(parsedQuery.filters);

    // Compute cosine similarity and apply metadata filters
    final results = <SearchResult>[];
    for (final candidate in candidates) {
      final score = _cosineSimilarity(queryEmbedding, candidate.vector);

      // Apply filter thresholds using metadata (redundant with _getCandidateEmbeddings but safe)
      final meta = await database.photoMetadata.getById(candidate.photoId);
      if (meta != null) {
        if (!await _matchesFilters(meta, parsedQuery.filters)) continue;
      } else if (parsedQuery.filters.hasLocation == true ||
          parsedQuery.filters.favoritesOnly == true) {
        continue;
      }

      results.add(
        SearchResult(photoId: candidate.photoId, score: score, metadata: meta),
      );
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

    final queryEmbedding = await embeddingProvider.generateEmbedding(
      imageBytes,
    );

    final candidates = await _getCandidateEmbeddings(filters);

    final results = <SearchResult>[];
    for (final candidate in candidates) {
      final score = _cosineSimilarity(queryEmbedding, candidate.vector);
      final meta = await database.photoMetadata.getById(candidate.photoId);
      if (meta == null) continue;
      if (filters != null && !await _matchesFilters(meta, filters)) continue;
      results.add(
        SearchResult(photoId: candidate.photoId, score: score, metadata: meta),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));

    // Apply ranking engine
    final rankedResults = await rankingEngine.rank(
      results.take(limit * 3).toList(),
      context: rankingContext,
    );

    return rankedResults.take(limit).toList();
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
    _logger.info('Searching for person: "$personName"');

    // Find person by name (case-insensitive)
    final person = await database.peopleDao.getByDisplayName(personName);
    if (person == null) {
      _logger.info('No person found with name: "$personName"');
      return [];
    }

    // Get all face photo IDs for this person
    final faces = await database.faces.getByPersonId(person.personId);
    if (faces.isEmpty) return [];

    final photoIds = faces.map((f) => f.photoId).toSet();

    // Build results
    final results = <SearchResult>[];
    for (final photoId in photoIds) {
      final meta = await database.photoMetadata.getById(photoId);
      if (meta == null) continue;
      if (filters != null && !await _matchesFilters(meta, filters)) continue;

      results.add(
        SearchResult(photoId: photoId, score: 1.0, metadata: meta),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));

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
      if (meta == null) continue;
      if (filters != null && !await _matchesFilters(meta, filters)) continue;
      results.add(
        SearchResult(photoId: candidate.photoId, score: score, metadata: meta),
      );
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
      SELECT e.photo_id, e.model, e.vector, e.created_at
      FROM embeddings e
      LEFT JOIN photo_metadata pm ON e.photo_id = pm.photo_id
      $favoritesJoin
      $personJoin
      $whereClause
      GROUP BY e.photo_id
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
    _logger.info('Preloading embedding cache for model: $_activeModelId');
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
      [...whereArgs, limit],
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

    _logger.info(
      'Cached ${_embeddingCache.length} embeddings for model $_activeModelId',
    );
  }
}
