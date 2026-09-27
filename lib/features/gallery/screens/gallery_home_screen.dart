import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:ai_gallery/core/utils/thumbnail_utils.dart';
import 'package:ai_gallery/core/widgets/shimmer_grid.dart';
import '../providers/gallery_providers.dart';
import '../providers/navigation_provider.dart';
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
import '../../assistant/screens/assistant_screen.dart';
import '../../home/screens/home_screen.dart';
import '../../memories/screens/memories_screen.dart';

/// Root shell with bottom navigation: Home | Photos | Albums | People | Memories.
class GalleryHomeScreen extends ConsumerStatefulWidget {
  const GalleryHomeScreen({super.key});

  @override
  ConsumerState<GalleryHomeScreen> createState() => _GalleryHomeScreenState();
}

class _GalleryHomeScreenState extends ConsumerState<GalleryHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final isSelecting = selection.isNotEmpty;
    final currentIndex = ref.watch(activeTabProvider);

    final screens = [
      const HomeScreen(),
      const _PhotosTab(),
      const _AlbumsTab(),
      const PeopleScreen(),
      const MemoriesScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          if (isSelecting) ref.read(selectionProvider.notifier).clear();
          ref.read(activeTabProvider.notifier).switchTo(i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_outlined),
            selectedIcon: Icon(Icons.photo),
            label: 'Photos',
          ),
          NavigationDestination(
            icon: Icon(Icons.album_outlined),
            selectedIcon: Icon(Icons.album),
            label: 'Albums',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Memories',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'assistant_fab',
        tooltip: 'AI Assistant',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AssistantScreen()),
          );
        },
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Photos Tab (chronological grid with date grouping)
// ─────────────────────────────────────────────

class _PhotosTab extends ConsumerStatefulWidget {
  const _PhotosTab();

  @override
  ConsumerState<_PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends ConsumerState<_PhotosTab>
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

    // Trigger album switch animation outside build to avoid setState during build.
    if (_previousAlbumId != selected) {
      final captured = selected;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _previousAlbumId != captured) {
          _triggerAlbumSwitch();
        } else if (mounted && _previousAlbumId == captured) {
          // First time: _previousAlbumId was null, need to trigger
          _triggerAlbumSwitch();
        }
      });
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
              key: const Key('photos_search_button'),
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
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
                loading: () => const ShimmerGrid(columns: 3),
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

// ─────────────────────────────────────────────
// Albums Tab (device albums grid)
// ─────────────────────────────────────────────

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        actions: [
          IconButton(
            key: const Key('albums_search_button'),
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            },
          ),
        ],
      ),
      body: albums.when(
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
        data: (albumList) {
          if (albumList.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.album_outlined,
                    size: 72,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No albums found',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your device albums will appear here.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.0,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: albumList.length,
            itemBuilder: (context, index) {
              final album = albumList[index];
              return _AlbumCard(album: album);
            },
          );
        },
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final AssetPathEntity album;

  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              child: FutureBuilder<List<AssetEntity>>(
                future: album.getAssetListRange(start: 0, end: 1),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return AssetEntityImage(
                      snapshot.data!.first,
                      isOriginal: false,
                      thumbnailSize: ThumbnailSizes.forGrid(context, 2, spacing: 8),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _albumPlaceholder(context);
                      },
                    );
                  }
                  return _albumPlaceholder(context);
                },
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  FutureBuilder<int>(
                    future: album.assetCountAsync,
                    builder: (context, snapshot) {
                      final count = snapshot.data;
                      return Text(
                        count != null ? '$count items' : 'Loading...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _albumPlaceholder(BuildContext context) {
    return Center(
      child: Icon(
        Icons.photo_library_outlined,
        size: 40,
        color: Theme.of(context)
            .colorScheme
            .onSurfaceVariant
            .withValues(alpha: 0.5),
      ),
    );
  }
}
