import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/ai/providers/local_embedding_provider.dart';
import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/domain/models/user_settings.dart';
import 'package:ai_gallery/features/search/services/search_service.dart';

// ─────────────────────────────────────────────
// Re-export types from search_service
// ─────────────────────────────────────────────

export '../services/search_service.dart' show SearchResult, SearchFilters;

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

/// Search results stream.
final searchResultsProvider = FutureProvider<List<SearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];

  final searchService = ref.watch(searchServiceProvider);
  return searchService.search(query, limit: 20);
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