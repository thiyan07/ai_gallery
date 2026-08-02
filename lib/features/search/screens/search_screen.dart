import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_providers.dart';
import '../../gallery/providers/gallery_providers.dart';

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
    final gridSize = ref.watch(gridSizeProvider);
    return _SearchResultsGrid(
      results: results,
      gridSize: gridSize,
      onTap: (result) {
        // TODO: Navigate to photo view
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

// ─────────────────────────────────────────────
// Search results grid with pinch-to-zoom
// ─────────────────────────────────────────────

class _SearchResultsGrid extends ConsumerStatefulWidget {
  final List<SearchResult> results;
  final int gridSize;
  final void Function(SearchResult) onTap;

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
  late Animation<int> _gridSizeAnimation;
  late AnimationController _overlayAnimationController;
  late Animation<double> _overlayOpacityAnimation;
  late Animation<double> _overlayScaleAnimation;

  int _currentGridSize = 3;
  int _targetGridSize = 3;
  double _pinchScale = 1.0;
  double _lastPinchScale = 1.0;
  bool _isPinching = false;
  static const double _pinchSensitivity = 0.4;

  @override
  void initState() {
    super.initState();
    _currentGridSize = widget.gridSize;
    _targetGridSize = widget.gridSize;

    _gridAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _gridSizeAnimation = IntTween(
      begin: _currentGridSize,
      end: _targetGridSize,
    ).animate(CurvedAnimation(
      parent: _gridAnimationController,
      curve: Curves.easeOutCubic,
    ));

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

    _gridAnimationController.addListener(_onGridAnimationTick);
  }

  void _onGridAnimationTick() {
    if (mounted) {
      setState(() {
        _currentGridSize = _gridSizeAnimation.value;
      });
    }
  }

  @override
  void didUpdateWidget(_SearchResultsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gridSize != widget.gridSize &&
        _targetGridSize == _currentGridSize) {
      _animateToGridSize(widget.gridSize);
    }
  }

  @override
  void dispose() {
    _gridAnimationController.removeListener(_onGridAnimationTick);
    _gridAnimationController.dispose();
    _overlayAnimationController.dispose();
    super.dispose();
  }

  void _animateToGridSize(int targetSize) {
    if (targetSize == _targetGridSize) return;

    _targetGridSize = targetSize.clamp(2, 6);
    _gridAnimationController.reset();
    _gridSizeAnimation = IntTween(
      begin: _currentGridSize,
      end: _targetGridSize,
    ).animate(CurvedAnimation(
      parent: _gridAnimationController,
      curve: Curves.easeOutCubic,
    ));
    _gridAnimationController.forward();

    // Show overlay with new grid size
    _showOverlay();

    // Persist the new grid size
    ref.read(gridSizeProvider.notifier).setSize(_targetGridSize);
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
    _lastPinchScale = 1.0;
    _isPinching = true;
    _overlayAnimationController.forward();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    _pinchScale = details.scale;

    // Calculate the target grid size based on pinch
    final scaleDelta = (_pinchScale - _lastPinchScale) * _pinchSensitivity;

    // Find the closest grid size
    double normalizedScale = (_targetGridSize - 3) + scaleDelta * 4;
    int newTarget = (normalizedScale + 3).round().clamp(2, 6);

    if (newTarget != _targetGridSize) {
      _animateToGridSize(newTarget);
      _lastPinchScale = _pinchScale;
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _pinchScale = 1.0;
    _lastPinchScale = 1.0;
    _isPinching = false;
    _overlayAnimationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.results;

    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: _handleScaleEnd,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _gridAnimationController,
            builder: (context, child) {
              return GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _currentGridSize,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: results.length,
                itemBuilder: (context, index) {
                  return _AnimatedSearchResultTile(
                    result: results[index],
                    gridSize: _currentGridSize,
                    onTap: () => widget.onTap(results[index]),
                  );
                },
              );
            },
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
                            '$_targetGridSize Columns',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onInverseSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Visual column indicator
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(_targetGridSize, (i) {
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
  final SearchResult result;
  final int gridSize;
  final VoidCallback onTap;

  const _AnimatedSearchResultTile({
    required this.result,
    required this.gridSize,
    required this.onTap,
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
        ),
      ),
    );
  }
}