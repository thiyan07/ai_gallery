import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../providers/gallery_providers.dart';
import '../providers/selection_provider.dart';
import '../widgets/photo_tile.dart';
import '../widgets/bulk_action_bar.dart';
import '../../settings/screens/settings_screen.dart';
import 'favorites_screen.dart';
import '../../search/search.dart';

/// Root shell with bottom navigation: Gallery | Favorites | Settings.
class GalleryHomeScreen extends ConsumerStatefulWidget {
  const GalleryHomeScreen({super.key});

  @override
  ConsumerState<GalleryHomeScreen> createState() => _GalleryHomeScreenState();
}

class _GalleryHomeScreenState extends ConsumerState<GalleryHomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final isSelecting = selection.isNotEmpty;

    final screens = [
      const _GalleryTab(),
      const FavoritesScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          if (isSelecting) ref.read(selectionProvider.notifier).clear();
          setState(() => _currentIndex = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.photo_outlined),
            selectedIcon: Icon(Icons.photo),
            label: 'Gallery',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: 'Favorites',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Gallery Tab
// ─────────────────────────────────────────────

class _GalleryTab extends ConsumerStatefulWidget {
  const _GalleryTab();

  @override
  ConsumerState<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends ConsumerState<_GalleryTab>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  bool _loadingMore = false;
  late AnimationController _albumSwitchController;
  late Animation<double> _albumSwitchAnimation;
  String? _previousAlbumId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    _albumSwitchController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _albumSwitchAnimation = CurvedAnimation(
      parent: _albumSwitchController,
      curve: Curves.easeOutCubic,
    );
    _albumSwitchController.value = 1.0;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _albumSwitchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    await ref.read(photoListProvider.notifier).loadMore();
    if (mounted) setState(() => _loadingMore = false);
  }

  void _triggerAlbumSwitch() {
    _albumSwitchController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final permAsync = ref.watch(mediaPermissionProvider);
    final albums = ref.watch(albumListProvider);
    final photos = ref.watch(photoListProvider);
    final selected = ref.watch(selectedAlbumProvider);
    final gridSize = ref.watch(gridSizeProvider);
    final selection = ref.watch(selectionProvider);
    final selectionNotifier = ref.read(selectionProvider.notifier);
    final isSelecting = selection.isNotEmpty;

    // Trigger animation when album changes
    if (_previousAlbumId != selected) {
      _triggerAlbumSwitch();
    }
    _previousAlbumId = selected;

    return Scaffold(
      appBar: AppBar(
        title: isSelecting
            ? Text('${selection.length} selected')
            : _AlbumDropdown(albums: albums, selectedAlbumId: selected),
        actions: [
          if (isSelecting) ...[
            TextButton(
              onPressed: () {
                final all = photos.value?.map((a) => a.id).toList() ?? [];
                selectionNotifier.selectAll(all);
              },
              child: const Text('All'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: selectionNotifier.clear,
            ),
          ] else ...[
            // Grid size slider button
            _GridSizeButton(gridSize: gridSize),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SearchScreen(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
      body: FadeTransition(
        opacity: _albumSwitchAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(_albumSwitchAnimation),
          child: permAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _permissionDeniedState(context),
            data: (granted) {
              if (!granted) return _permissionDeniedState(context);

              return photos.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_off,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading albums',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please try again or check your storage permissions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                        onPressed: () {
                          ref.refresh(albumListProvider);
                          ref.refresh(mediaPermissionProvider);
                        },
                      ),
                    ],
                  ),
                ),
                data: (photoList) {
                  if (photoList.isEmpty) {
                    return _emptyState(context);
                  }
                  return Stack(
                    children: [
                      _PinchZoomGrid(
                        photoList: photoList,
                        initialGridSize: gridSize,
                        scrollController: _scrollController,
                        loadingMore: _loadingMore,
                        onLoadMore: _loadNextPage,
                        onRefresh: () async {
                          await ref.read(photoListProvider.notifier).refresh();
                        },
                      ),

                      // Bulk action bar floats at the bottom
                      if (isSelecting)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: BulkActionBar(allAssets: photos.value ?? []),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _permissionDeniedState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 72,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Photo access required',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'AI Gallery needs access to your photos to display and organize them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Settings'),
              onPressed: () {
                PhotoManager.openSetting();
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.read(mediaPermissionProvider.notifier).refresh(),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 72,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No photos found',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'This album appears to be empty.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Album dropdown in AppBar title
// ─────────────────────────────────────────────

class _AlbumDropdown extends ConsumerWidget {
  final AsyncValue<List<AssetPathEntity>> albums;
  final String? selectedAlbumId;

  const _AlbumDropdown({required this.albums, required this.selectedAlbumId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return albums.when(
      loading: () => const Text('Loading…'),
      error: (_, __) => const Text('AI Gallery'),
      data: (list) {
        if (list.isEmpty) return const Text('AI Gallery');
        final current = list.firstWhere(
          (album) => album.id == selectedAlbumId,
          orElse: () => list.first,
        );
        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedAlbumId ?? current.id,
            isDense: true,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            onChanged: (albumId) {
              ref.read(selectedAlbumProvider.notifier).select(albumId);
            },
            items: list
                .map(
                  (a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(a.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Pinch-to-zoom photo grid with smooth transitions
// ─────────────────────

class _PinchZoomGrid extends ConsumerStatefulWidget {
  final List<AssetEntity> photoList;
  final int initialGridSize;
  final ScrollController scrollController;
  final bool loadingMore;
  final VoidCallback? onLoadMore;
  final VoidCallback? onRefresh;

  const _PinchZoomGrid({
    required this.photoList,
    required this.initialGridSize,
    required this.scrollController,
    this.loadingMore = false,
    this.onLoadMore,
    this.onRefresh,
  });

  @override
  ConsumerState<_PinchZoomGrid> createState() => _PinchZoomGridState();
}

class _PinchZoomGridState extends ConsumerState<_PinchZoomGrid> with TickerProviderStateMixin {
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

  // Grid size thresholds for pinch gesture
  static const List<int> _gridSizes = [2, 3, 4, 5, 6];

  @override
  void initState() {
    super.initState();
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
  void didUpdateWidget(_PinchZoomGrid oldWidget) {
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
              return RefreshIndicator(
                onRefresh: widget.onRefresh == null
                    ? () async {}
                    : () => Future<void>.value(),
                child: GridView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.all(2),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _currentGridSize,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: photoList.length + (widget.loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == photoList.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return _AnimatedPhotoTile(
                      asset: photoList[index],
                      allAssets: photoList,
                      index: index,
                      gridSize: _currentGridSize,
                    );
                  },
                ),
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

/// Animated photo tile that responds to grid size changes
class _AnimatedPhotoTile extends StatefulWidget {
  final AssetEntity asset;
  final List<AssetEntity> allAssets;
  final int index;
  final int gridSize;

  const _AnimatedPhotoTile({
    required this.asset,
    required this.allAssets,
    required this.index,
    required this.gridSize,
  });

  @override
  State<_AnimatedPhotoTile> createState() => _AnimatedPhotoTileState();
}

class _AnimatedPhotoTileState extends State<_AnimatedPhotoTile>
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
  void didUpdateWidget(_AnimatedPhotoTile oldWidget) {
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
// Grid size popup button
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
