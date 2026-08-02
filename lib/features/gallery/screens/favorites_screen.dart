import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../providers/gallery_providers.dart';
import '../providers/favorites_provider.dart';
import '../widgets/photo_tile.dart';

/// Shows only the photos the user has starred.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritesProvider);
    final photos = ref.watch(photoListProvider);
    final gridSize = ref.watch(gridSizeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: [
          _GridSizeButton(gridSize: gridSize),
          favs.when(
            data: (ids) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: Text('${ids.length}'),
                avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: favs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (favoriteIds) {
          if (favoriteIds.isEmpty) {
            return _emptyState(context);
          }

          return photos.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (allPhotos) {
              final favPhotos = allPhotos
                  .where((a) => favoriteIds.contains(a.id))
                  .toList();

              if (favPhotos.isEmpty) {
                return _emptyState(context);
              }

              return _FavoritesPinchZoomGrid(
                photoList: favPhotos,
                initialGridSize: gridSize,
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.star_border_rounded,
            size: 72,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No favorites yet',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap ★ on any photo to add it here.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinch-to-zoom grid for favorites
class _FavoritesPinchZoomGrid extends ConsumerStatefulWidget {
  final List<AssetEntity> photoList;
  final int initialGridSize;

  const _FavoritesPinchZoomGrid({
    required this.photoList,
    required this.initialGridSize,
  });

  @override
  ConsumerState<_FavoritesPinchZoomGrid> createState() => _FavoritesPinchZoomGridState();
}

class _FavoritesPinchZoomGridState extends ConsumerState<_FavoritesPinchZoomGrid>
    with TickerProviderStateMixin {
  late AnimationController _gridAnimationController;
  late Animation<int> _gridSizeAnimation;
  late AnimationController _overlayAnimationController;
  late Animation<double> _overlayOpacityAnimation;
  late Animation<double> _overlayScaleAnimation;
  late ScrollController _scrollController;

  int _currentGridSize = 3;
  int _targetGridSize = 3;
  double _pinchScale = 1.0;
  double _lastPinchScale = 1.0;
  bool _isPinching = false;
  static const double _pinchSensitivity = 0.4;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _currentGridSize = widget.initialGridSize;
    _targetGridSize = widget.initialGridSize;

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
  void didUpdateWidget(_FavoritesPinchZoomGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGridSize != widget.initialGridSize &&
        _targetGridSize == _currentGridSize) {
      _animateToGridSize(widget.initialGridSize);
    }
  }

  @override
  void dispose() {
    _gridAnimationController.removeListener(_onGridAnimationTick);
    _gridAnimationController.dispose();
    _overlayAnimationController.dispose();
    _scrollController.dispose();
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
    final photoList = widget.photoList;

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
                controller: _scrollController,
                padding: const EdgeInsets.all(2),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _currentGridSize,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: photoList.length,
                itemBuilder: (context, index) {
                  return _AnimatedFavoritesPhotoTile(
                    asset: photoList[index],
                    allAssets: photoList,
                    index: index,
                    gridSize: _currentGridSize,
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

/// Animated photo tile for favorites that responds to grid size changes
class _AnimatedFavoritesPhotoTile extends StatefulWidget {
  final AssetEntity asset;
  final List<AssetEntity> allAssets;
  final int index;
  final int gridSize;

  const _AnimatedFavoritesPhotoTile({
    required this.asset,
    required this.allAssets,
    required this.index,
    required this.gridSize,
  });

  @override
  State<_AnimatedFavoritesPhotoTile> createState() => _AnimatedFavoritesPhotoTileState();
}

class _AnimatedFavoritesPhotoTileState extends State<_AnimatedFavoritesPhotoTile>
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
  void didUpdateWidget(_AnimatedFavoritesPhotoTile oldWidget) {
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
        child: PhotoTile(
          asset: widget.asset,
          allAssets: widget.allAssets,
          index: widget.index,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Grid size popup button (local copy)
// ─────────────────────────────────────────────

class _GridSizeButton extends ConsumerWidget {
  final int gridSize;
  const _GridSizeButton({required this.gridSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<int>(
      initialValue: gridSize,
      icon: const Icon(Icons.grid_view),
      tooltip: 'Grid size (pinch to zoom)',
      onSelected: (v) => ref.read(gridSizeProvider.notifier).setSize(v),
      itemBuilder: (_) => [2, 3, 4, 5, 6]
          .map(
            (n) => PopupMenuItem(
              value: n,
              child: Row(
                children: [
                  Icon(
                    Icons.grid_on,
                    size: 18,
                    color: n == gridSize
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text('$n columns'),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
