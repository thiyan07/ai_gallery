import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ai_gallery/features/search/providers/search_providers.dart';
import '../providers/favorites_provider.dart';

/// Full-screen photo viewer with swipe navigation, zoom, and action bar.
class PhotoViewScreen extends ConsumerStatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;

  const PhotoViewScreen({
    super.key,
    required this.assets,
    required this.initialIndex,
  });

  @override
  ConsumerState<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends ConsumerState<PhotoViewScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showBars = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  AssetEntity get _current => widget.assets[_currentIndex];

  void _toggleBars() => setState(() => _showBars = !_showBars);

  Future<void> _share() async {
    final file = await _current.file;
    if (file != null) {
      await Share.shareXFiles([XFile(file.path)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final favs = ref.watch(favoritesProvider);
    final isFav = favs.value?.contains(_current.id) ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showBars
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              elevation: 0,
              title: Text(
                '${_currentIndex + 1} / ${widget.assets.length}',
                style: const TextStyle(fontSize: 15),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    isFav ? Icons.star : Icons.star_border,
                    color: isFav ? Colors.amber : Colors.white,
                  ),
                  onPressed: () =>
                      ref.read(favoritesProvider.notifier).toggle(_current.id),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined, color: Colors.white),
                  onPressed: _share,
                ),
                IconButton(
                  icon: const Icon(Icons.search_outlined, color: Colors.white),
                  tooltip: 'Find Similar',
                  onPressed: _findSimilar,
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.white),
                  onPressed: () => _showDetails(context),
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: _toggleBars,
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.assets.length,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          itemBuilder: (context, index) {
            final asset = widget.assets[index];
            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Center(
                child: AssetEntityImage(
                  asset,
                  isOriginal: true,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _findSimilar() async {
    final searchService = ref.read(searchServiceProvider);
    final results = await searchService.searchSimilar(_current.id, limit: 20);

    if (!mounted) return;

    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No similar photos found'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Navigate to photo view screen with similar photos
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SimilarPhotosScreen(
          searchResults: results,
          originalAsset: _current,
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final asset = _current;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Photo Details',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _DetailRow(label: 'Filename', value: asset.title ?? '—'),
              _DetailRow(
                label: 'Dimensions',
                value: '${asset.width} × ${asset.height}',
              ),
              _DetailRow(
                label: 'Type',
                value: asset.type == AssetType.video ? 'Video' : 'Image',
              ),
              _DetailRow(
                label: 'Date taken',
                value: asset.createDateTime.toLocal().toString().split('.')[0],
              ),
              if (asset.type == AssetType.video)
                _DetailRow(
                  label: 'Duration',
                  value:
                      '${asset.duration ~/ 60}:${(asset.duration % 60).toString().padLeft(2, '0')}',
                ),
              if (asset.latitude != null && asset.longitude != null)
                _DetailRow(
                  label: 'Location',
                  value:
                      '${asset.latitude!.toStringAsFixed(4)}, ${asset.longitude!.toStringAsFixed(4)}',
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen showing similar photos found via visual search.
class _SimilarPhotosScreen extends ConsumerStatefulWidget {
  final List<RankedSearchResult> searchResults;
  final AssetEntity originalAsset;

  const _SimilarPhotosScreen({
    required this.searchResults,
    required this.originalAsset,
  });

  @override
  ConsumerState<_SimilarPhotosScreen> createState() =>
      _SimilarPhotosScreenState();
}

class _SimilarPhotosScreenState extends ConsumerState<_SimilarPhotosScreen> {
  late List<AssetEntity> _similarAssets;
  late List<RankedSearchResult> _currentResults;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _currentResults = List.from(widget.searchResults);
    _loadSimilarAssets();
  }

  Future<void> _loadSimilarAssets() async {
    try {
      // Fetch AssetEntity objects for the photo IDs
      final photoIds = _currentResults.map((r) => r.photoId).toSet();
      final allAssets = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );
      final matchingAssets = <AssetEntity>[];

      for (final assetPath in allAssets) {
        final assets = await assetPath.getAssetListPaged(page: 0, size: 10000);
        for (final asset in assets) {
          if (photoIds.contains(asset.id)) {
            matchingAssets.add(asset);
          }
        }
      }

      // Sort to match the search results order
      final idToIndex = {
        for (var i = 0; i < _currentResults.length; i++)
          _currentResults[i].photoId: i,
      };
      matchingAssets.sort(
        (a, b) => (idToIndex[a.id] ?? 999).compareTo(idToIndex[b.id] ?? 999),
      );

      if (mounted) {
        setState(() {
          _similarAssets = matchingAssets;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _similarAssets = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Similar to "${widget.originalAsset.title ?? 'Photo'}"',
          style: const TextStyle(fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_outlined, color: Colors.white),
            tooltip: 'Find More Similar',
            onPressed: _findMoreSimilar,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _similarAssets.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, color: Colors.white54, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'No similar photos found',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: _similarAssets.length,
              itemBuilder: (context, index) {
                final asset = _similarAssets[index];
                final result = _currentResults.firstWhere(
                  (r) => r.photoId == asset.id,
                  orElse: () => _currentResults[index],
                );
                return GestureDetector(
                  onTap: () => _openPhotoView(index),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AssetEntityImage(
                        asset,
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize.square(300),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Text(
                            '${(result.score * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _findMoreSimilar() async {
    // Use the first similar result as the new reference
    if (_similarAssets.isNotEmpty) {
      final searchService = ref.read(searchServiceProvider);
      final results = await searchService.searchSimilar(
        _similarAssets[0].id,
        limit: 20,
      );

      if (!mounted) return;

      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No more similar photos found')),
        );
        return;
      }

      final photoIds = results.map((r) => r.photoId).toSet();
      final allAssets = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );
      final matchingAssets = <AssetEntity>[];

      for (final assetPath in allAssets) {
        final assets = await assetPath.getAssetListPaged(page: 0, size: 10000);
        for (final asset in assets) {
          if (photoIds.contains(asset.id)) {
            matchingAssets.add(asset);
          }
        }
      }

      final idToIndex = {
        for (var i = 0; i < results.length; i++) results[i].photoId: i,
      };
      matchingAssets.sort(
        (a, b) => (idToIndex[a.id] ?? 999).compareTo(idToIndex[b.id] ?? 999),
      );

      if (mounted) {
        setState(() {
          _similarAssets = matchingAssets;
          _currentResults = results;
        });
      }
    }
  }

  void _openPhotoView(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PhotoViewScreen(assets: _similarAssets, initialIndex: index),
      ),
    );
  }
}
