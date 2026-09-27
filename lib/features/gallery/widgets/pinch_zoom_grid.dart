import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:ai_gallery/core/utils/thumbnail_utils.dart';
import '../providers/gallery_providers.dart';
import 'photo_tile.dart';

/// Pinch-to-zoom photo grid with smooth continuous transitions.
class PinchZoomGrid extends ConsumerStatefulWidget {
  final List<AssetEntity> photoList;
  final int initialGridSize;
  final ScrollController scrollController;
  final bool loadingMore;
  final VoidCallback? onLoadMore;
  final RefreshCallback? onRefresh;

  const PinchZoomGrid({
    super.key,
    required this.photoList,
    required this.initialGridSize,
    required this.scrollController,
    this.loadingMore = false,
    this.onLoadMore,
    this.onRefresh,
  });

  @override
  ConsumerState<PinchZoomGrid> createState() => _PinchZoomGridState();
}

class _PinchZoomGridState extends ConsumerState<PinchZoomGrid>
    with TickerProviderStateMixin {
  late AnimationController _gridAnimationController;
  late AnimationController _overlayAnimationController;
  late Animation<double> _overlayOpacityAnimation;
  late Animation<double> _overlayScaleAnimation;

  void Function(AnimationStatus)? _gridAnimationStatusListener;

  static const List<int> _gridSizes = [2, 3, 4, 5, 6];

  int _currentGridSizeIndex = 1;
  int _targetGridSizeIndex = 1;
  double _initialPinchScale = 1.0;
  double _currentPinchScale = 1.0;
  bool _isPinching = false;

  // Timeline scrubber state (Immich/AOSP-style fast scroll with date bubble).
  bool _scrubbing = false;
  String _scrubLabel = '';
  double _lastRowHeight = 0;

  @override
  void initState() {
    super.initState();
    _currentGridSizeIndex = _gridSizes.indexOf(
      widget.initialGridSize.clamp(2, 6),
    );
    if (_currentGridSizeIndex < 0) _currentGridSizeIndex = 1;
    _targetGridSizeIndex = _currentGridSizeIndex;

    _gridAnimationController = AnimationController(
      duration: const Duration(milliseconds: 450),
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
  void didUpdateWidget(PinchZoomGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGridSize != widget.initialGridSize &&
        _targetGridSizeIndex == _currentGridSizeIndex) {
      final newIndex = _gridSizes.indexOf(widget.initialGridSize.clamp(2, 6));
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
      Future.delayed(const Duration(milliseconds: 1000), () {
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

    if (scaleRatio > 1.15 && _targetGridSizeIndex > 0) {
      newTargetIndex = _targetGridSizeIndex - 1;
    } else if (scaleRatio < 0.87 &&
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

  /// Height of one grid row in logical pixels (square tiles + spacing).
  double _rowHeight(BuildContext context, int columns) {
    const spacing = 2.0;
    const padding = 2.0;
    final width = MediaQuery.sizeOf(context).width - padding * 2;
    return (width - spacing * (columns - 1)) / columns + spacing;
  }

  /// Date label for the item at [index] (clamped into the photo list).
  String _dateLabelFor(int index) {
    final photos = widget.photoList;
    if (photos.isEmpty) return '';
    final clamped = index.clamp(0, photos.length - 1);
    final date = photos[clamped].createDateTime;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    final label = '${months[date.month]} ${date.day}';
    return date.year == now.year ? label : '$label ${date.year}';
  }

  /// First-visible item index for a scroll [offset].
  int _indexForOffset(double offset, double rowHeight, int columns) {
    if (rowHeight <= 0) return 0;
    return (offset / rowHeight).floor() * columns;
  }

  void _onScrubStart(double localY, double stripHeight) {
    _onScrubUpdate(localY, stripHeight);
    setState(() => _scrubbing = true);
  }

  void _onScrubUpdate(double localY, double stripHeight) {
    final controller = widget.scrollController;
    if (!controller.hasClients || stripHeight <= 0) return;
    final max = controller.position.maxScrollExtent;
    if (max <= 0) return;
    final fraction = (localY / stripHeight).clamp(0.0, 1.0);
    final offset = fraction * max;
    controller.jumpTo(offset);
    final columns = _gridSizes[_currentGridSizeIndex];
    setState(() {
      _scrubLabel =
          _dateLabelFor(_indexForOffset(offset, _lastRowHeight, columns));
    });
  }

  void _onScrubEnd() {
    setState(() => _scrubbing = false);
  }

  @override
  Widget build(BuildContext context) {
    final photoList = widget.photoList;
    final currentGridSize = _gridSizes[_currentGridSizeIndex];
    // Decode thumbnails at the actual tile size × DPR instead of a fixed
    // 300px — at 5-6 columns this cuts per-tile decode work dramatically.
    final thumbnailSize = ThumbnailSizes.forGrid(context, currentGridSize);
    _lastRowHeight = _rowHeight(context, currentGridSize);

    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: _handleScaleEnd,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh:
                widget.onRefresh ??
                (() async {
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                }),
            child: GridView.builder(
              controller: widget.scrollController,
              // Keep a few rows of tiles alive off-screen so fast flings
              // don't rebuild/decode tiles every frame.
              cacheExtent: 800,
              padding: const EdgeInsets.all(2),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: currentGridSize,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: 1.0,
              ),
              itemCount: photoList.length + (widget.loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == photoList.length) {
                  return const Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                // RepaintBoundary keeps a scrolling tile from repainting
                // its neighbors every frame.
                return RepaintBoundary(
                  child: AnimatedPhotoTile(
                    key: ValueKey(photoList[index].id),
                    asset: photoList[index],
                    allAssets: photoList,
                    index: index,
                    gridSize: currentGridSize,
                    thumbnailSize: thumbnailSize,
                  ),
                );
              },
              semanticChildCount: photoList.length,
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
          // Timeline scrubber: right-edge drag strip with date bubble.
          if (photoList.length > 20)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 28,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stripHeight = constraints.maxHeight;
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: (d) => _onScrubStart(
                      d.localPosition.dy,
                      stripHeight,
                    ),
                    onVerticalDragUpdate: (d) => _onScrubUpdate(
                      d.localPosition.dy,
                      stripHeight,
                    ),
                    onVerticalDragEnd: (_) => _onScrubEnd(),
                    onVerticalDragCancel: _onScrubEnd,
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: _scrubbing ? 0.9 : 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_scrubbing && _scrubLabel.isNotEmpty)
            Positioned(
              right: 36,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.inverseSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _scrubLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onInverseSurface,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Animated photo tile with smooth scale/opacity transitions.
class AnimatedPhotoTile extends StatefulWidget {
  final AssetEntity asset;
  final List<AssetEntity> allAssets;
  final int index;
  final int gridSize;

  /// Decoded thumbnail resolution, forwarded to [PhotoTile].
  final ThumbnailSize thumbnailSize;

  const AnimatedPhotoTile({
    super.key,
    required this.asset,
    required this.allAssets,
    required this.index,
    required this.gridSize,
    this.thumbnailSize = const ThumbnailSize.square(300),
  });

  @override
  State<AnimatedPhotoTile> createState() => _AnimatedPhotoTileState();
}

class _AnimatedPhotoTileState extends State<AnimatedPhotoTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _slideAnimation;
  bool _shouldAnimate = true;

  @override
  void initState() {
    super.initState();
    // Fix #4: Only animate first 30 tiles to avoid 500 simultaneous controllers
    // causing jank on mid-tier devices. Remaining tiles render without animation.
    _shouldAnimate = widget.index < 30;
    if (!_shouldAnimate) {
      // No controller needed — will build directly
      _controller = AnimationController(vsync: this, duration: Duration.zero);
      _scaleAnimation = AlwaysStoppedAnimation(1.0);
      _opacityAnimation = AlwaysStoppedAnimation(1.0);
      _slideAnimation = AlwaysStoppedAnimation(0.0);
      return;
    }
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    final delay = (widget.index % 10) * 15;
    _slideAnimation = Tween<double>(begin: 0.12, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(delay / 1000.0, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedPhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_shouldAnimate) return;
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
    if (!_shouldAnimate) {
      return PhotoTile(
        asset: widget.asset,
        allAssets: widget.allAssets,
        index: widget.index,
        thumbnailSize: widget.thumbnailSize,
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value * 40),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          ),
        );
      },
      child: PhotoTile(
        asset: widget.asset,
        allAssets: widget.allAssets,
        index: widget.index,
        thumbnailSize: widget.thumbnailSize,
      ),
    );
  }
}
