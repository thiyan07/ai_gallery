import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';
import 'package:ai_gallery/features/search/services/search_service.dart';
import 'package:ai_gallery/features/search/services/natural_language_parser.dart';
import 'package:ai_gallery/features/search/services/ranking_engine.dart';
import 'package:ai_gallery/features/search/services/search_suggestion_service.dart';

// ─────────────────────────────────────────────
// Re-export embedding provider from core/di/providers.dart
// ───────────────────────

/// Re-export the embedding provider from core/di/providers.dart
/// This supports local, BYOK, and hybrid modes with cloud fallback.
export 'package:ai_gallery/core/di/providers.dart' show embeddingProviderProvider;

// ─────────────────────────────────────────────
// Re-export types from search_service
// ─────────────────────────────────────────────

export '../services/search_service.dart' show SearchResult, SearchFilters;
export '../services/natural_language_parser.dart' show ParsedQuery, NaturalLanguageParser;
export '../services/ranking_engine.dart' show RankingEngine, RankedSearchResult, RankingContext;
export '../services/search_suggestion_service.dart' show SearchSuggestionService, SearchSuggestion, SuggestionType;

// ─────────────────────────────────────────────
// Natural Language Parser Provider
// ────────────

/// Natural language query parser provider.
/// Fetches active person names so the parser can recognize people in queries.
final naturalLanguageParserProvider = FutureProvider<NaturalLanguageParser>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  final database = ref.watch(appDatabaseProvider).requireValue;

  // Fetch active person names for person recognition in search queries
  final people = await database.peopleDao.getAllActive();
  final personNames = people
      .where((p) => p.displayName != null && p.displayName!.isNotEmpty)
      .map((p) => p.displayName!)
      .toList();

  return NaturalLanguageParser.withLogger(logger, personNames: personNames);
});

/// Parsed query provider - parses the search query and provides structured filters.
final parsedQueryProvider = FutureProvider<ParsedQuery>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final parserAsync = ref.watch(naturalLanguageParserProvider);

  if (query.trim().isEmpty) {
    return ParsedQuery(
      semanticQuery: '',
      filters: SearchFilters(),
      confidence: 0.0,
      originalQuery: query,
    );
  }

  final parser = await parserAsync.when(
    data: (p) => p,
    loading: () => NaturalLanguageParser(),
    error: (_, __) => NaturalLanguageParser(),
  );

  return parser.parse(query);
});

// ─────────────────────────────────────────────
// Ranking Engine Provider
// ─────────────────────────────────────────────

/// Ranking engine for combining search signals.
final rankingEngineProvider = Provider<RankingEngine>((ref) {
  final database = ref.watch(appDatabaseProvider).requireValue;
  final logger = ref.watch(appLoggerProvider);
  return RankingEngine(database: database, logger: logger);
});

// ─────────────────────────────────────────────
// Search Suggestion Service Provider
// ─────────────────────────────────────────────

/// Search suggestion service for recent/popular/autocomplete suggestions.
final searchSuggestionServiceProvider = Provider<SearchSuggestionService>((ref) {
  final database = ref.watch(appDatabaseProvider).requireValue;
  final logger = ref.watch(appLoggerProvider);
  final service = SearchSuggestionService(database: database, logger: logger);
  // Initialize the table asynchronously
  unawaited(service.initialize());
  return service;
});

/// Fallback embedding provider used while the real model is still loading
/// or when no provider is available. Throws MODEL_NOT_READY so
/// SearchService can gracefully fall back to OCR-only search.
class _FallbackEmbeddingProvider implements EmbeddingProvider {
  @override
  String get id => 'fallback';
  @override
  String get name => 'Fallback (loading)';
  @override
  String get modelId => 'unknown';
  @override
  Future<bool> get isAvailable async => false;
  @override
  Future<Float32List> generateEmbedding(Uint8List _) =>
      throw StateError('MODEL_NOT_READY');
  @override
  Future<Float32List> generateTextEmbedding(String _) =>
      throw StateError('MODEL_NOT_READY');
  @override
  Future<Float32List> generateEmbeddingFromFace({
    required Uint8List imageBytes,
    required FaceDetection faceDetection,
  }) =>
      throw StateError('MODEL_NOT_READY');
  @override
  Future<void> initialize() async {}
  @override
  Future<void> warmUp() async {}
  @override
  Future<void> dispose() async {}
}

/// Search service for semantic/text search.
/// Handles AsyncLoading by falling back to OCR-only via _FallbackEmbeddingProvider.
final searchServiceProvider = Provider<SearchService>((ref) {
  final embeddingAsync = ref.watch(embeddingProviderProvider);
  final database = ref.watch(appDatabaseProvider).requireValue;
  final rankingEngine = ref.watch(rankingEngineProvider);
  final suggestionService = ref.watch(searchSuggestionServiceProvider);

  final EmbeddingProvider effectiveProvider =
      embeddingAsync.maybeWhen(
        data: (p) => p,
        orElse: () => null,
      ) ??
      _FallbackEmbeddingProvider() as EmbeddingProvider;

  return SearchService(
    embeddingProvider: effectiveProvider,
    database: database,
    rankingEngine: rankingEngine,
    suggestionService: suggestionService,
  );
});

/// Provider to check if semantic search is available (model loaded and ready).
final semanticSearchAvailableProvider = FutureProvider<bool>((ref) async {
  final embeddingProviderAsync = ref.watch(embeddingProviderProvider);
  return embeddingProviderAsync.when(
    data: (provider) async {
      if (provider == null) return false;
      return provider.isAvailable;
    },
    loading: () => false,
    error: (_, __) => false,
  );
});

// ─────────────────────────────────────────────
// Search State
// ─────────────────────────────────────────────

/// Current search query.
final searchQueryProvider = Provider<String>((ref) {
  return ref.watch(_searchQueryNotifierProvider);
});

/// The notifier for the search query - used by UI to modify the query.
final searchQueryNotifierProvider = _searchQueryNotifierProvider;

final _searchQueryNotifierProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
  void clear() => state = '';
}

/// Search results stream using natural language parsing.
/// This watches the parsed query provider and uses the semantic query + filters for search.
///
/// NOTE: Search must NOT throw MODEL_NOT_READY when the embedding model is missing —
/// [SearchService] already handles graceful fallback to OCR-only and person/object
/// paths. Throwing here previously made every search show an error even though
/// OCR text search could still return results.
final searchResultsProvider = FutureProvider<List<RankedSearchResult>>((ref) async {
  // Watch the parsed query which includes both semantic query and extracted filters
  final parsedQueryAsync = ref.watch(parsedQueryProvider);
  // Also watch manual filters
  final manualFilters = ref.watch(searchFiltersProvider);

  return parsedQueryAsync.when(
    data: (parsedQuery) async {
      if (parsedQuery.semanticQuery.trim().isEmpty) return [];

      // Combine parsed filters with manual filters
      final combinedFilters = parsedQuery.filters.copyWith(
        minQualityScore: manualFilters.minQualityScore ?? parsedQuery.filters.minQualityScore,
        maxBlurScore: manualFilters.maxBlurScore ?? parsedQuery.filters.maxBlurScore,
        dateFrom: manualFilters.dateFrom ?? parsedQuery.filters.dateFrom,
        dateTo: manualFilters.dateTo ?? parsedQuery.filters.dateTo,
        hasLocation: manualFilters.hasLocation || parsedQuery.filters.hasLocation,
        cameraMake: manualFilters.cameraMake ?? parsedQuery.filters.cameraMake,
        cameraModel: manualFilters.cameraModel ?? parsedQuery.filters.cameraModel,
        albumId: manualFilters.albumId ?? parsedQuery.filters.albumId,
        folderPath: manualFilters.folderPath ?? parsedQuery.filters.folderPath,
        mediaType: manualFilters.mediaType ?? parsedQuery.filters.mediaType,
        orientation: manualFilters.orientation ?? parsedQuery.filters.orientation,
        favoritesOnly: manualFilters.favoritesOnly || parsedQuery.filters.favoritesOnly,
        minWidth: manualFilters.minWidth ?? parsedQuery.filters.minWidth,
        maxWidth: manualFilters.maxWidth ?? parsedQuery.filters.maxWidth,
        minHeight: manualFilters.minHeight ?? parsedQuery.filters.minHeight,
        maxHeight: manualFilters.maxHeight ?? parsedQuery.filters.maxHeight,
        personName: manualFilters.personName ?? parsedQuery.filters.personName,
      );

      final searchService = ref.watch(searchServiceProvider);
      // Use the new searchParsed method that handles semantic query + filters + ranking
      final updatedParsedQuery = parsedQuery.copyWith(filters: combinedFilters);
      return searchService.searchParsed(updatedParsedQuery, limit: 20);
    },
    loading: () => [],
    error: (e, st) {
      ref.read(appLoggerProvider).error('Search error', error: e, stackTrace: st);
      return [];
    },
  );
});

/// Search filters state.
final searchFiltersProvider =
    NotifierProvider<SearchFiltersNotifier, SearchFilters>(
  SearchFiltersNotifier.new,
);

class SearchFiltersNotifier extends Notifier<SearchFilters> {  @override
  SearchFilters build() => SearchFilters();

  void setMinQuality(double? quality) {
    state = state.copyWith(minQualityScore: quality);
  }

  void setMaxBlur(double? blur) {
    state = state.copyWith(maxBlurScore: blur);
  }

  void setDateRange(DateTime? from, DateTime? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
  }

  void setHasLocation(bool hasLocation) {
    state = state.copyWith(hasLocation: hasLocation);
  }

  void setAlbumId(String? albumId) {
    state = state.copyWith(albumId: albumId);
  }

  void setFolderPath(String? folderPath) {
    state = state.copyWith(folderPath: folderPath);
  }

  void setMediaType(String? mediaType) {
    state = state.copyWith(mediaType: mediaType);
  }

  void setOrientation(int? orientation) {
    state = state.copyWith(orientation: orientation);
  }

  void setFavoritesOnly(bool favoritesOnly) {
    state = state.copyWith(favoritesOnly: favoritesOnly);
  }

  void setPersonName(String? personName) {
    state = state.copyWith(personName: personName);
  }

  void setDimensions({int? minWidth, int? maxWidth, int? minHeight, int? maxHeight}) {
    state = state.copyWith(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  void clear() {
    state = SearchFilters();
  }
}

// ─────────────────────────────────────────────
// Index coverage (semantic indexing completeness)
// ─────────────────────────────────────────────

/// How many photos have semantic embeddings vs total photos.
/// Photos without embeddings are invisible to meaning-based search.
class IndexCoverage {
  const IndexCoverage({
    required this.totalPhotos,
    required this.embeddedPhotos,
  });

  final int totalPhotos;
  final int embeddedPhotos;

  int get unindexed => (totalPhotos - embeddedPhotos).clamp(0, totalPhotos);
  bool get isComplete => unindexed == 0;
}

final indexCoverageProvider = FutureProvider<IndexCoverage>((ref) async {
  final database = ref.watch(appDatabaseProvider).requireValue;
  final totalRows = await database.database
      .rawQuery('SELECT COUNT(*) as cnt FROM photo_metadata');
  final embeddedRows = await database.database.rawQuery(
    'SELECT COUNT(DISTINCT photo_id) as cnt FROM embeddings',
  );
  final total = (totalRows.first['cnt'] as int?) ?? 0;
  final embedded = (embeddedRows.first['cnt'] as int?) ?? 0;
  return IndexCoverage(totalPhotos: total, embeddedPhotos: embedded);
});