import 'dart:math';
import 'dart:typed_data';

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/embedding.dart';
import '../../../domain/models/photo_metadata.dart';
import '../../../ai/providers/embedding_provider.dart';

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
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final double? minQualityScore;
  final double? maxBlurScore;
  final bool hasLocation;
  final String? cameraMake;
  final String? cameraModel;

  SearchFilters copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    double? minQualityScore,
    double? maxBlurScore,
    bool? hasLocation,
    String? cameraMake,
    String? cameraModel,
  }) {
    return SearchFilters(
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      minQualityScore: minQualityScore ?? this.minQualityScore,
      maxBlurScore: maxBlurScore ?? this.maxBlurScore,
      hasLocation: hasLocation ?? this.hasLocation,
      cameraMake: cameraMake ?? this.cameraMake,
      cameraModel: cameraModel ?? this.cameraModel,
    );
  }
}

/// Service for performing semantic search over photo embeddings.
class SearchService {
  SearchService({
    required this.embeddingProvider,
    required this.database,
    AppLogger? logger,
  }) : _logger = logger ?? const ConsoleAppLogger();

  final EmbeddingProvider embeddingProvider;
  final AppDatabase database;
  final AppLogger _logger;

  /// In-memory cache of embeddings for fast search.
  final Map<String, Embedding> _embeddingCache = {};

  /// Maximum embeddings to cache in memory.
  static const _maxCacheSize = 10000;

  /// Performs a text-based semantic search.
  Future<List<SearchResult>> search(
    String query, {
    int limit = 20,
    SearchFilters? filters,
    EmbeddingProvider? customProvider,
  }) async {
    if (query.trim().isEmpty) return [];

    final provider = customProvider ?? embeddingProvider;

    _logger.info('Searching for: "$query"');

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
        if (filters?.minQualityScore != null &&
            (meta.qualityScore ?? 0) < filters!.minQualityScore!) {
          continue;
        }
        if (filters?.maxBlurScore != null &&
            (meta.blurScore ?? 1.0) > filters!.maxBlurScore!) {
          continue;
        }
        if (filters?.dateFrom != null || filters?.dateTo != null) {
          if (meta.dateCreated != null) {
            if (filters!.dateFrom != null &&
                meta.dateCreated!.isBefore(filters.dateFrom!)) {
              continue;
            }
            if (filters.dateTo != null &&
                meta.dateCreated!.isAfter(filters.dateTo!)) {
              continue;
            }
          }
        }
        if (filters?.hasLocation == true &&
            (meta.latitude == null || meta.longitude == null)) {
          continue;
        }
        if (filters?.cameraMake != null &&
            meta.cameraMake != filters!.cameraMake) {
          continue;
        }
        if (filters?.cameraModel != null &&
            meta.cameraModel != filters!.cameraModel) {
          continue;
        }
      } else if (filters?.hasLocation == true) {
        // No metadata - skip if location required
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

    // Apply limit
    return results.take(limit).toList();
  }

  /// Search by image (reverse image search).
  Future<List<SearchResult>> searchByImage(
    Uint8List imageBytes, {
    int limit = 20,
    SearchFilters? filters,
  }) async {
    _logger.info('Reverse image search');

    final queryEmbedding = await embeddingProvider.generateEmbedding(imageBytes);

    final candidates = await _getCandidateEmbeddings(filters);

    final results = <SearchResult>[];
    for (final candidate in candidates) {
      final score = _cosineSimilarity(queryEmbedding, candidate.vector);
      results.add(SearchResult(
        photoId: candidate.photoId,
        score: score,
        metadata: await database.photoMetadata.getById(candidate.photoId),
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }

  /// Search for similar photos to a given photo ID.
  Future<List<SearchResult>> searchSimilar(
    String photoId, {
    int limit = 20,
    SearchFilters? filters,
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
      results.add(SearchResult(
        photoId: candidate.photoId,
        score: score,
        metadata: await database.photoMetadata.getById(candidate.photoId),
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }

  /// Get all embeddings matching filters (with caching).
  Future<List<Embedding>> _getCandidateEmbeddings(SearchFilters? filters) async {
    // If cache is populated and no complex filters, use cache
    if (_embeddingCache.isNotEmpty &&
        (filters == null ||
            (filters.dateFrom == null &&
                filters.dateTo == null &&
                filters.minQualityScore == null &&
                filters.maxBlurScore == null &&
                !filters.hasLocation &&
                filters.cameraMake == null &&
                filters.cameraModel == null))) {
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

    final whereClause = whereConditions.isEmpty
        ? ''
        : 'WHERE ${whereConditions.join(' AND ')}';

    final rows = await database.database.rawQuery('''
      SELECT e.photo_id, e.model, e.vector, e.created_at
      FROM embeddings e
      LEFT JOIN photo_metadata pm ON e.photo_id = pm.photo_id
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