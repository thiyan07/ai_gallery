import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../providers/gallery_providers.dart';
import '../providers/selection_provider.dart';
import '../widgets/bulk_action_bar.dart';
import '../widgets/album_dropdown.dart';
import '../widgets/pinch_zoom_grid.dart';
import '../widgets/grid_size_button.dart';
import '../../settings/screens/settings_screen.dart';
import '../../settings/screens/local_models_screen.dart';
import 'favorites_screen.dart';
import '../../search/search.dart';
import '../../people/screens/people_screen.dart';

/// Root shell with bottom navigation: Gallery | Favorites | People | Settings.
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
      const PeopleScreen(),
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
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
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

    if (_previousAlbumId != selected) {
      _triggerAlbumSwitch();
    }
    _previousAlbumId = selected;

    return Scaffold(
      appBar: AppBar(
        title: isSelecting
            ? Text('${selection.length} selected')
            : AlbumDropdown(albums: albums, selectedAlbumId: selected),
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
            GridSizeButton(gridSize: gridSize),
            IconButton(
              icon: const Icon(Icons.memory),
              tooltip: 'Recommended AI Model',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LocalModelsScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SearchScreen()));
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
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
                          ref.invalidate(albumListProvider);
                          ref.invalidate(mediaPermissionProvider);
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
                      PinchZoomGrid(
                        photoList: photoList,
                        initialGridSize: gridSize,
                        scrollController: _scrollController,
                        loadingMore: _loadingMore,
                        onLoadMore: _loadNextPage,
                        onRefresh: () async {
                          await ref.read(photoListProvider.notifier).refresh();
                        },
                      ),
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
              onPressed: () => PhotoManager.openSetting(),
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
