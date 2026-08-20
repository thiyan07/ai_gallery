import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../providers/search_providers.dart';
import '../../gallery/providers/gallery_providers.dart';
import '../../../../core/di/providers.dart';
import 'search_result_tile.dart';

/// Grid of search results with pinch-to-zoom support.
class SearchResultsGrid extends ConsumerStatefulWidget {
  final List<RankedSearchResult> results;
  final int gridSize;
  final void Function(RankedSearchResult) onTap;

  const SearchResultsGrid({
    super.key,
    required this.results,
    required this.gridSize,
    required this.onTap,
  });

  @override
  ConsumerState<SearchResultsGrid> createState() => _SearchResultsGridState();
}

class _SearchResultsGridState extends ConsumerState<SearchResultsGrid>
    with TickerProviderStateMixin {
  late AnimationController _gridAnimationController;
  late AnimationController _overlayAnimationController;
  late Animation<double> _overlayOpacityAnimation;
  late Animation<double> _overlayScaleAnimation;

  static const List<int> _gridSizes = [2, 3, 4, 5, 6];

  int _currentGridSizeIndex = 1;
  int _targetGridSizeIndex = 1;
  double _initialPinchScale = 1.0;
  double _currentPinchScale = 1.0;
  bool _isPinching = false;

  void Function(AnimationStatus)? _gridAnimationStatusListener;

  final Map<String, AssetEntity> _assetEntities = {};

  @override
  void initState() {
    super.initState();
    _currentGridSizeIndex = _gridSizes.indexOf(widget.gridSize.clamp(2, 6));
    if (_currentGridSizeIndex < 0) _currentGridSizeIndex = 1;
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
      CurvedAnimation(
        parent: _overlayAnimationController,
        curve: Curves.easeOut,
      ),
    );
    _overlayScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _overlayAnimationController,
        curve: Curves.easeOutBack,
      ),
    );

    _gridAnimationStatusListener = (status) => _onGridAnimationStatus(status);
    _gridAnimationController.addStatusListener(_gridAnimationStatusListener!);
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
      if (mounted) {
        setState(() {
          _currentGridSizeIndex = _targetGridSizeIndex;
        });
      }
    }
  }

  @override
  void didUpdateWidget(SearchResultsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.results != widget.results) {
      _loadAssetEntities();
    }
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
    if (_gridAnimationStatusListener != null) {
      _gridAnimationController.removeStatusListener(
        _gridAnimationStatusListener!,
      );
    }
    _gridAnimationController.dispose();
    _overlayAnimationController.dispose();
    super.dispose();
  }

  void _animateToGridSizeIndex(int targetIndex) {
    if (targetIndex == _targetGridSizeIndex) return;

    _targetGridSizeIndex = targetIndex.clamp(0, _gridSizes.length - 1);
    _gridAnimationController.reset();
    _gridAnimationController.forward();
    _showOverlay();
    ref
        .read(gridSizeProvider.notifier)
        .setSize(_gridSizes[_targetGridSizeIndex]);
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
    final scaleRatio = _currentPinchScale / _initialPinchScale;

    int newTargetIndex = _targetGridSizeIndex;

    if (scaleRatio > 1.25 && _targetGridSizeIndex > 0) {
      newTargetIndex = _targetGridSizeIndex - 1;
    } else if (scaleRatio < 0.8 &&
        _targetGridSizeIndex < _gridSizes.length - 1) {
      newTargetIndex = _targetGridSizeIndex + 1;
    }

    if (newTargetIndex != _targetGridSizeIndex) {
      _animateToGridSizeIndex(newTargetIndex);
      _initialPinchScale = _currentPinchScale;
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
                return AnimatedSearchResultTile(
                  result: result,
                  gridSize: currentGridSize,
                  onTap: () => widget.onTap(result),
                  asset: asset,
                );
              },
            ),
          ),
          AnimatedBuilder(
            animation: _overlayAnimationController,
            builder: (context, child) {
              return Opacity(
                opacity: _overlayOpacityAnimation.value,
                child: Transform.scale(
                  scale: _overlayScaleAnimation.value,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onInverseSurface,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_gridSizes[_targetGridSizeIndex]} Columns',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onInverseSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              _gridSizes[_targetGridSizeIndex],
                              (i) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onInverseSurface
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                );
                              },
                            ),
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

/// Animated search result tile that responds to grid size changes.
class AnimatedSearchResultTile extends StatefulWidget {
  final RankedSearchResult result;
  final int gridSize;
  final VoidCallback onTap;
  final AssetEntity? asset;

  const AnimatedSearchResultTile({
    super.key,
    required this.result,
    required this.gridSize,
    required this.onTap,
    this.asset,
  });

  @override
  State<AnimatedSearchResultTile> createState() =>
      _AnimatedSearchResultTileState();
}

class _AnimatedSearchResultTileState extends State<AnimatedSearchResultTile>
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
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedSearchResultTile oldWidget) {
    super.didUpdateWidget(oldWidget);
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
        child: SearchResultTile(
          result: widget.result,
          onTap: widget.onTap,
          asset: widget.asset,
        ),
      ),
    );
  }
}
