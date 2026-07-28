import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_providers.dart';

/// Search screen with text and image search capabilities.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    ref.read(searchQueryNotifierProvider.notifier).setQuery(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);
    final parsedQueryAsync = ref.watch(parsedQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search photos...',
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(searchQueryNotifierProvider.notifier).clear();
                    },
                  )
                : null,
          ),
          style: theme.textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_list : Icons.filter_list_off),
            onPressed: () => setState(() => _showFilters = !_showFilters),
            tooltip: 'Filters',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showFilters) _buildFiltersBar(theme),
          // Show parsed NLQ filters if any were detected
          parsedQueryAsync.when(
            data: (parsedQuery) {
              if (parsedQuery.hasFilters && parsedQuery.originalQuery != null) {
                return _buildParsedFiltersBar(theme, parsedQuery);
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Expanded(
            child: resultsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => _buildErrorState(context, e.toString()),
              data: (results) {
                if (query.isEmpty) {
                  return _buildEmptySearchView(
                    onCameraSearch: () {
                      // TODO: Implement camera search
                    },
                    onVoiceSearch: () {
                      // TODO: Implement voice search
                    },
                  );
                }
                if (results.isEmpty) {
                  return _buildNoResults(context, query);
                }
                return _buildResultsGrid(theme, results);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersBar(ThemeData theme) {
    final filters = ref.watch(searchFiltersProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              theme,
              label: 'Quality',
              selected: filters.minQualityScore != null,
              onTap: () {
                // TODO: Show quality slider dialog
              },
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              theme,
              label: 'Date Range',
              selected: filters.dateFrom != null || filters.dateTo != null,
              onTap: () {
                // TODO: Show date range picker
              },
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              theme,
              label: 'Location',
              selected: filters.hasLocation,
              onTap: () {
                ref.read(searchFiltersProvider.notifier).setHasLocation(!filters.hasLocation);
              },
            ),
            if (filters.minQualityScore != null ||
                filters.dateFrom != null ||
                filters.dateTo != null ||
                filters.hasLocation) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  ref.read(searchFiltersProvider.notifier).clear();
                },
                child: const Text('Clear All'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Shows automatically parsed filters from natural language query.
  Widget _buildParsedFiltersBar(ThemeData theme, ParsedQuery parsedQuery) {
    final filters = parsedQuery.filters;
    final parsedChips = <Widget>[];

    if (filters.dateFrom != null || filters.dateTo != null) {
      String dateLabel = 'Date: ';
      if (filters.dateFrom != null && filters.dateTo != null) {
        dateLabel += '${_formatDate(filters.dateFrom!)} – ${_formatDate(filters.dateTo!)}';
      } else if (filters.dateFrom != null) {
        dateLabel += 'from ${_formatDate(filters.dateFrom!)}';
      } else {
        dateLabel += 'until ${_formatDate(filters.dateTo!)}';
      }
      parsedChips.add(_buildParsedFilterChip(theme, label: dateLabel, icon: Icons.calendar_today));
    }

    if (filters.cameraMake != null || filters.cameraModel != null) {
      String cameraLabel = 'Camera: ';
      if (filters.cameraMake != null && filters.cameraModel != null) {
        cameraLabel += '${filters.cameraMake} ${filters.cameraModel}';
      } else if (filters.cameraMake != null) {
        cameraLabel += filters.cameraMake!;
      } else {
        cameraLabel += filters.cameraModel!;
      }
      parsedChips.add(_buildParsedFilterChip(theme, label: cameraLabel, icon: Icons.camera_alt));
    }

    if (filters.minQualityScore != null || filters.maxBlurScore != null) {
      String qualityLabel = 'Quality: ';
      if (filters.minQualityScore != null && filters.maxBlurScore != null) {
        qualityLabel += 'High quality, low blur';
      } else if (filters.minQualityScore != null) {
        qualityLabel += 'Min quality ${(filters.minQualityScore! * 100).toInt()}%';
      } else {
        qualityLabel += 'Max blur ${(filters.maxBlurScore! * 100).toInt()}%';
      }
      parsedChips.add(_buildParsedFilterChip(theme, label: qualityLabel, icon: Icons.high_quality));
    }

    if (filters.hasLocation) {
      parsedChips.add(_buildParsedFilterChip(theme, label: 'Has location', icon: Icons.location_on));
    }

    if (parsedChips.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.psychology,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Understood from query',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(parsedQuery.confidence * 100).toInt()}% confident',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: parsedChips,
          ),
        ],
      ),
    );
  }

  Widget _buildParsedFilterChip(ThemeData theme, {required String label, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildFilterChip(
    ThemeData theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: theme.colorScheme.primaryContainer,
      checkmarkColor: theme.colorScheme.onPrimaryContainer,
    );
  }

  Widget _buildResultsGrid(ThemeData theme, List<SearchResult> results) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return _SearchResultTile(
          result: result,
          onTap: () {
            // Navigate to photo view
          },
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Search Failed',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              onPressed: () => ref.invalidate(searchResultsProvider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults(BuildContext context, String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No results for "$query"',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different keywords or check your spelling.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearchView({
    required VoidCallback onCameraSearch,
    required VoidCallback onVoiceSearch,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Search your photos',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Type to search by description, objects, colors, or scenes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: onVoiceSearch,
                  icon: const Icon(Icons.mic),
                  label: const Text('Voice'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onCameraSearch,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.onTap,
  });

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail placeholder
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.secondaryContainer,
                  ],
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.image,
                  size: 32,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // Score badge
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${(result.score * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}