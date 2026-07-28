import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/ai/providers/local_embedding_provider.dart';
import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/domain/models/user_settings.dart';
import 'package:ai_gallery/features/search/services/search_service.dart';
import 'package:ai_gallery/features/search/services/natural_language_parser.dart';

// ─────────────────────────────────────────────
// Re-export types from search_service
// ─────────────────────────────────────────────

export '../services/search_service.dart' show SearchResult, SearchFilters;
export '../services/natural_language_parser.dart' show ParsedQuery, NaturalLanguageParser;

// ─────────────────────────────────────────────
// Natural Language Parser Provider
// ─────────────────────────────────────────────

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
// Embedding Provider (uses core/providers.dart)
// ─────────────────────────────────────────────

/// Local embedding provider (ONNX Runtime + SigLIP/CLIP).
/// This uses a FutureProvider to asynchronously create the provider
/// based on user settings.
final embeddingProviderProvider = FutureProvider<EmbeddingProvider?>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  final settings = ref.watch(userSettingsProvider);
  final modelManager = ref.watch(modelManagerProvider);

  if (settings.aiMode == AiMode.local) {
    return LocalEmbeddingProvider(
      logger: logger,
      modelManager: modelManager,
    );
  }

  // TODO: Add cloud providers (OpenAI, Google Vision, Anthropic)
  // For hybrid/BYOK modes, return appropriate cloud provider
  // if (settings.aiMode == AiMode.byok || settings.aiMode == AiMode.hybrid) {
  //   return CloudEmbeddingProvider(...);
  // }

  return null;
});

// ─────────────────────────────────────────────
// Search Service
// ─────────────────────────────────────────────

/// Search service for semantic/text search.
/// Uses requireValue on the async providers to get the resolved values.
final searchServiceProvider = Provider<SearchService>((ref) {
  final embeddingProvider = ref.watch(embeddingProviderProvider).requireValue;
  final database = ref.watch(appDatabaseProvider).requireValue;

  return SearchService(
    embeddingProvider: embeddingProvider!,
    database: database,
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
final searchResultsProvider = FutureProvider<List<SearchResult>>((ref) async {
  // Watch the parsed query which includes both semantic query and extracted filters
  final parsedQueryAsync = ref.watch(parsedQueryProvider);

  return parsedQueryAsync.when(
    data: (parsedQuery) async {
      if (parsedQuery.semanticQuery.trim().isEmpty) return [];

      final searchService = ref.watch(searchServiceProvider);
      // Use the new searchParsed method that handles semantic query + filters
      return searchService.searchParsed(parsedQuery, limit: 20);
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

  void setDateRange(DateTime? from, DateTime? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
  }

  void setHasLocation(bool hasLocation) {
    state = state.copyWith(hasLocation: hasLocation);
  }

  void clear() {
    state = SearchFilters();
  }
}