import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../providers/search_providers.dart';
import '../../gallery/providers/gallery_providers.dart';
import '../../gallery/screens/photo_view_screen.dart';
import '../../../../core/di/providers.dart';
import '../../../../domain/repositories/photo_repository.dart';

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
    final semanticAvailableAsync = ref.watch(semanticSearchAvailableProvider);

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
                    semanticAvailable: semanticAvailableAsync.value ?? false,
                  );
                }
                if (results.isEmpty) {
                  return _buildNoResults(context, query, semanticAvailable: semanticAvailableAsync.value ?? true);
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
    final filtersNotifier = ref.read(searchFiltersProvider.notifier);
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
              selected: filters.minQualityScore != null || filters.maxBlurScore != null,
              onTap: () => _showQualityDialog(context, theme, filters, filtersNotifier),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              theme,
              label: 'Date Range',
              selected: filters.dateFrom != null || filters.dateTo != null,
              onTap: () => _showDateRangeDialog(context, theme, filters, filtersNotifier),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              theme,
              label: 'Location',
              selected: filters.hasLocation,
              onTap: () {
                filtersNotifier.setHasLocation(!filters.hasLocation);
              },
            ),
            if (filters.minQualityScore != null ||
                filters.maxBlurScore != null ||
                filters.dateFrom != null ||
                filters.dateTo != null ||
                filters.hasLocation) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  filtersNotifier.clear();
                },
                child: const Text('Clear All'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showQualityDialog(
    BuildContext context,
    ThemeData theme,
    SearchFilters filters,
    SearchFiltersNotifier notifier,
  ) async {
    double minQuality = filters.minQualityScore ?? 0.0;
    double maxBlur = filters.maxBlurScore ?? 1.0;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Quality Filters'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Minimum Quality Score', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Slider(
                value: minQuality,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label: '${(minQuality * 100).round()}%',
                onChanged: (value) => setState(() => minQuality = value),
              ),
              const SizedBox(height: 16),
              Text('Maximum Blur Score', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Slider(
                value: maxBlur,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label: '${(maxBlur * 100).round()}%',
                onChanged: (value) => setState(() => maxBlur = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                notifier.setMinQuality(null);
                notifier.setMaxBlur(null);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                notifier.setMinQuality(minQuality > 0 ? minQuality : null);
                notifier.setMaxBlur(maxBlur < 1 ? maxBlur : null);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDateRangeDialog(
    BuildContext context,
    ThemeData theme,
    SearchFilters filters,
    SearchFiltersNotifier notifier,
  ) async {
    DateTime? from = filters.dateFrom;
    DateTime? to = filters.dateTo;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Date Range'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('From'),
                subtitle: Text(
                  from != null ? _formatDate(from!) : 'Not selected',
                  style: theme.textTheme.bodyMedium,
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: dialogContext,
                    initialDate: from ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) setState(() => from = date);
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('To'),
                subtitle: Text(
                  to != null ? _formatDate(to!) : 'Not selected',
                  style: theme.textTheme.bodyMedium,
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: dialogContext,
                    initialDate: to ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) setState(() => to = date);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                notifier.setDateRange(null, null);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                notifier.setDateRange(from, to);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Apply'),
            ),
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

  Widget _buildResultsGrid(ThemeData theme, List<RankedSearchResult> results) {
    final gridSize = ref.watch(gridSizeProvider);
    return _SearchResultsGrid(
      results: results,
      gridSize: gridSize,
      onTap: (result) => _navigateToPhotoView(context, result),
    );
  }

  Future<void> _navigateToPhotoView(BuildContext context, RankedSearchResult result) async {
    // Get all photo IDs from current results to enable swipe navigation
    final allResults = ref.read(searchResultsProvider);
    final photoIds = allResults.when(
      data: (results) => results.map((r) => r.photoId).toList(),
      loading: () => <String>[result.photoId],
      error: (_, __) => <String>[result.photoId],
    );

    // Fetch all assets for the swipe gallery
    final photoRepo = ref.read(photoRepositoryProvider);
    final assets = await photoRepo.getAssetsByIds(photoIds);

    if (!context.mounted || assets.isEmpty) return;

    // Find the index of the tapped photo
    final initialIndex = assets.indexWhere((a) => a.id == result.photoId);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewScreen(
          assets: assets,
          initialIndex: initialIndex >= 0 ? initialIndex : 0,
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    final isModelNotReady = error.contains('MODEL_NOT_READY');
    final theme = Theme.of(context);

    if (isModelNotReady) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'AI Model Required',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Semantic search requires a local AI model. Please download the model from Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Open AI Models'),
                onPressed: () {
                  Navigator.of(context).pushNamed('/settings/local-models');
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () => ref.invalidate(searchResultsProvider),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Search Failed',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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

  Widget _buildNoResults(BuildContext context, String query, {bool semanticAvailable = true}) {
    final theme = Theme.of(context);

    // If semantic search is not available, show model required state
    if (!semanticAvailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'AI Model Required',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Semantic search requires a local AI model. Please download the model from Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Open AI Models'),
                onPressed: () {
                  Navigator.of(context).pushNamed('/settings/local-models');
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () => ref.invalidate(searchResultsProvider),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No results for "$query"',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different keywords or check your spelling.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearchView({
    required VoidCallback onCameraSearch,
    required VoidCallback onVoiceSearch,
    required bool semanticAvailable,
  }) {
    final theme = Theme.of(context);

    // If semantic search is not available, show model required state
    if (!semanticAvailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'AI Model Required for Semantic Search',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Download a local AI model to enable natural language photo search.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Open AI Models'),
                onPressed: () {
                  Navigator.of(context).pushNamed('/settings/local-models');
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Check Again'),
                onPressed: () => ref.invalidate(semanticSearchAvailableProvider),
              ),
            ],
          ),
        ),
      );
    }

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
    this.asset,
  });

  final RankedSearchResult result;
  final VoidCallback onTap;
  final AssetEntity? asset;

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
          children: <Widget>[
            // Thumbnail
            if (asset != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AssetEntityImage(
                  asset!,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(300),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                    ),
                  ),
                ),
              )
            else
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

// ─────────────────────────────────────────────
// Search results grid with pinch-to-zoom
// ─────────────────────────────────────────────

class _SearchResultsGrid extends ConsumerStatefulWidget {
  final List<RankedSearchResult> results;
  final int gridSize;
  final void Function(RankedSearchResult) onTap;

  const _SearchResultsGrid({
    required this.results,
    required this.gridSize,
    required this.onTap,
  });

  @override
  ConsumerState<_SearchResultsGrid> createState() => _SearchResultsGridState();
}

class _SearchResultsGridState extends ConsumerState<_SearchResultsGrid>
    with TickerProviderStateMixin {
  late AnimationController _gridAnimationController;
  late AnimationController _overlayAnimationController;
  late Animation<double> _overlayOpacityAnimation;
  late Animation<double> _overlayScaleAnimation;

  // Grid sizes: [2, 3, 4, 5, 6] mapped to indices 0-4
  static const List<int> _gridSizes = [2, 3, 4, 5, 6];

  int _currentGridSizeIndex = 1; // Default to 3 columns (index 1)
  int _targetGridSizeIndex = 1;
  double _initialPinchScale = 1.0;
  double _currentPinchScale = 1.0;
  bool _isPinching = false;

  // Map of photoId to AssetEntity for thumbnail loading
  final Map<String, AssetEntity> _assetEntities = {};

  @override
  void initState() {
    super.initState();
    _currentGridSizeIndex = _gridSizes.indexOf(widget.gridSize.clamp(2, 6));
    if (_currentGridSizeIndex < 0) _currentGridSizeIndex = 1; // Default to 3
    _targetGridSizeIndex = _currentGridSizeIndex;
    _loadAssetEntities();

    _gridAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _overlayAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _overlayOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _overlayAnimationController, curve: Curves.easeOut),
    );
    _overlayScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _overlayAnimationController, curve: Curves.easeOutBack),
    );

    _gridAnimationController.addStatusListener((status) => _onGridAnimationStatus(status));
  }

  Future<void> _loadAssetEntities() async {
    final photoIds = widget.results.map((r) => r.photoId).toList();
    final photoRepo = ref.read(photoRepositoryProvider);
    final assets = await photoRepo.getAssetsByIds(photoIds);

    final Map<String, AssetEntity> entityMap = {};
    for (final asset in assets) {
      entityMap[asset.id] = asset;
    }

    if (mounted) {
      setState(() {
        _assetEntities.clear();
        _assetEntities.addAll(entityMap);
      });
    }
  }

  void _onGridAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // Update the current index to target once animation completes
      if (mounted) {
        setState(() {
          _currentGridSizeIndex = _targetGridSizeIndex;
        });
      }
    }
  }

  @override
  void didUpdateWidget(_SearchResultsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.results != widget.results) {
      _loadAssetEntities();
    }
    // Trigger animation when grid size changes
    if (oldWidget.gridSize != widget.gridSize &&
        _targetGridSizeIndex == _currentGridSizeIndex) {
      final newIndex = _gridSizes.indexOf(widget.gridSize.clamp(2, 6));
      if (newIndex >= 0) {
        _animateToGridSizeIndex(newIndex);
      }
    }
  }

  @override
  void dispose() {
    _gridAnimationController.removeStatusListener((status) => _onGridAnimationStatus(status));
    _gridAnimationController.dispose();
    _overlayAnimationController.dispose();
    super.dispose();
  }

  void _animateToGridSizeIndex(int targetIndex) {
    if (targetIndex == _targetGridSizeIndex) return;

    _targetGridSizeIndex = targetIndex.clamp(0, _gridSizes.length - 1);
    _gridAnimationController.reset();
    _gridAnimationController.forward();

    // Show overlay with new grid size
    _showOverlay();

    // Persist the new grid size
    ref.read(gridSizeProvider.notifier).setSize(_gridSizes[_targetGridSizeIndex]);
  }

  void _showOverlay() {
    _overlayAnimationController.forward(from: 0.0).then((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && !_isPinching) {
          _overlayAnimationController.reverse();
        }
      });
    });
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _initialPinchScale = 1.0;
    _currentPinchScale = 1.0;
    _isPinching = true;
    _overlayAnimationController.forward();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    _currentPinchScale = details.scale;

    // Calculate scale relative to initial pinch position
    // A pinch out (scale > initial) increases grid size (fewer columns)
    // A pinch in (scale < initial) decreases grid size (more columns)
    final scaleRatio = _currentPinchScale / _initialPinchScale;

    // Map scale ratio to grid size index change
    // scaleRatio > 1.25 -> decrease index (fewer columns, zoom in)
    // scaleRatio < 0.8 -> increase index (more columns, zoom out)
    // This gives roughly 25% threshold between grid size steps
    int newTargetIndex = _targetGridSizeIndex;

    if (scaleRatio > 1.25 && _targetGridSizeIndex > 0) {
      newTargetIndex = _targetGridSizeIndex - 1;
    } else if (scaleRatio < 0.8 && _targetGridSizeIndex < _gridSizes.length - 1) {
      newTargetIndex = _targetGridSizeIndex + 1;
    }

    if (newTargetIndex != _targetGridSizeIndex) {
      _animateToGridSizeIndex(newTargetIndex);
      _initialPinchScale = _currentPinchScale; // Reset baseline
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _currentPinchScale = 1.0;
    _initialPinchScale = 1.0;
    _isPinching = false;
    _overlayAnimationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.results;
    final currentGridSize = _gridSizes[_currentGridSizeIndex];

    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: _handleScaleEnd,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await Future<void>.delayed(const Duration(milliseconds: 300));
            },
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: currentGridSize,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                final asset = _assetEntities[result.photoId];
                return _AnimatedSearchResultTile(
                  result: result,
                  gridSize: currentGridSize,
                  onTap: () => widget.onTap(result),
                  asset: asset,
                );
              },
            ),
          ),

          // Grid size indicator overlay
          AnimatedBuilder(
            animation: _overlayAnimationController,
            builder: (context, child) {
              return Opacity(
                opacity: _overlayOpacityAnimation.value,
                child: Transform.scale(
                  scale: _overlayScaleAnimation.value,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.grid_view_rounded,
                            size: 32,
                            color: Theme.of(context).colorScheme.onInverseSurface,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_gridSizes[_targetGridSizeIndex]} Columns',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onInverseSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Visual column indicator
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(_gridSizes[_targetGridSizeIndex], (i) {
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.onInverseSurface.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Animated search result tile that responds to grid size changes
class _AnimatedSearchResultTile extends StatefulWidget {
  final RankedSearchResult result;
  final int gridSize;
  final VoidCallback onTap;
  final AssetEntity? asset;

  const _AnimatedSearchResultTile({
    required this.result,
    required this.gridSize,
    required this.onTap,
    this.asset,
  });

  @override
  State<_AnimatedSearchResultTile> createState() => _AnimatedSearchResultTileState();
}

class _AnimatedSearchResultTileState extends State<_AnimatedSearchResultTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(_AnimatedSearchResultTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger animation when grid size changes
    if (oldWidget.gridSize != widget.gridSize) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: _SearchResultTile(
          result: widget.result,
          onTap: widget.onTap,
          asset: widget.asset,
        ),
      ),
    );
  }
}