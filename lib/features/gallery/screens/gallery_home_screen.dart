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

class _GalleryTabState extends ConsumerState<_GalleryTab> {
  final ScrollController _scrollController = ScrollController();
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
    // loadMore now reads the current album internally
    setState(() => _loadingMore = true);
    await ref.read(photoListProvider.notifier).loadMore();
    if (mounted) setState(() => _loadingMore = false);
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
      body: permAsync.when(
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
                  RefreshIndicator(
                    onRefresh: () async {
                      await ref.read(photoListProvider.notifier).refresh();
                    },
                    child: GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(2),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridSize,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemCount: photoList.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == photoList.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        return PhotoTile(
                          asset: photoList[index],
                          allAssets: photoList,
                          index: index,
                        );
                      },
                    ),
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
      tooltip: 'Grid size',
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
