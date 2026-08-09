import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/ai/providers/local_embedding_provider.dart';
import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/domain/models/user_settings.dart';
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
final naturalLanguageParserProvider = Provider<NaturalLanguageParser>((ref) {
  final logger = ref.watch(appLoggerProvider);
  return NaturalLanguageParser.withLogger(logger);
});

/// Parsed query provider - parses the search query and provides structured filters.
final parsedQueryProvider = FutureProvider<ParsedQuery>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final parser = ref.watch(naturalLanguageParserProvider);

  if (query.trim().isEmpty) {
    return ParsedQuery(
      semanticQuery: '',
      filters: SearchFilters(),
      confidence: 0.0,
      originalQuery: query,
    );
  }

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

/// Search service for semantic/text search.
/// Uses requireValue on the async providers to get the resolved values.
final searchServiceProvider = Provider<SearchService>((ref) {
  final embeddingProvider = ref.watch(embeddingProviderProvider).requireValue;
  final database = ref.watch(appDatabaseProvider).requireValue;
  final rankingEngine = ref.watch(rankingEngineProvider);
  final suggestionService = ref.watch(searchSuggestionServiceProvider);

  return SearchService(
    embeddingProvider: embeddingProvider!,
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
final searchResultsProvider = FutureProvider<List<RankedSearchResult>>((ref) async {
  // Watch the parsed query which includes both semantic query and extracted filters
  final parsedQueryAsync = ref.watch(parsedQueryProvider);
  // Also watch manual filters
  final manualFilters = ref.watch(searchFiltersProvider);
  // Check if semantic search is available
  final semanticAvailableAsync = ref.watch(semanticSearchAvailableProvider);

  return parsedQueryAsync.when(
    data: (parsedQuery) async {
      if (parsedQuery.semanticQuery.trim().isEmpty) return [];

      // Check if semantic search is available (model loaded)
      final available = await semanticAvailableAsync.when(
        data: (value) => value,
        loading: () => false,
        error: (_, __) => false,
      );
      if (!available) {
        // Throw a specific error that the UI can catch and display
        throw StateError('MODEL_NOT_READY: Semantic search model is not available. Please download the required AI model from Settings > AI Models.');
      }

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

class SearchFiltersNotifier extends Notifier<SearchFilters> {
  @override
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