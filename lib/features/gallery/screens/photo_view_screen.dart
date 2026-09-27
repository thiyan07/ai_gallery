import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
import 'package:ai_gallery/features/search/providers/search_providers.dart';
import '../../../core/di/providers.dart' as di_providers;
import '../providers/favorites_provider.dart';
import '../providers/gallery_providers.dart';
import '../services/media_service.dart';
import '../../editing/screens/edit_screen.dart';

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
  bool _slideshow = false;
  bool _slideshowRepeat = true;
  bool _slideshowShuffle = false;
  Timer? _slideshowTimer;
  final _random = math.Random();

  /// Seconds each photo stays on screen during a slideshow.
  static const _slideDuration = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    // Warm the neighbors so the first swipe doesn't hitch on decode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheNeighbors(_currentIndex);
    });
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  AssetEntity get _current => widget.assets[_currentIndex];

  /// Toggle automatic slideshow playback (4s per photo).
  void _toggleSlideshow() {
    if (_slideshow) {
      _slideshowTimer?.cancel();
      setState(() {
        _slideshow = false;
        _showBars = true;
      });
      return;
    }
    if (widget.assets.length < 2) return;
    setState(() {
      _slideshow = true;
      _showBars = false;
    });
    _slideshowTimer = Timer.periodic(_slideDuration, (_) {
      if (!mounted) return;
      var next = _currentIndex + 1;
      if (_slideshowShuffle && widget.assets.length > 1) {
        // Random next photo, never the same one twice in a row.
        do {
          next = _random.nextInt(widget.assets.length);
        } while (next == _currentIndex);
      } else if (next >= widget.assets.length) {
        if (_slideshowRepeat) {
          next = 0;
          _pageController.jumpToPage(0);
          setState(() => _currentIndex = 0);
          _precacheNeighbors(0);
          return;
        }
        _toggleSlideshow();
        return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
      if (_slideshowShuffle) {
        _pageController.jumpToPage(next);
        setState(() => _currentIndex = next);
        _precacheNeighbors(next);
      }
    });
  }

  /// Pre-decode the previous/next full photos so swiping never waits on IO.
  void _precacheNeighbors(int index) {
    for (final neighbor in [index - 1, index + 1]) {
      if (neighbor < 0 || neighbor >= widget.assets.length) continue;
      final asset = widget.assets[neighbor];
      // Precaching must not crash the viewer if the asset is unreadable.
      precacheImage(
        AssetEntityImageProvider(asset, isOriginal: true),
        context,
      ).ignore();
    }
  }

  void _toggleBars() => setState(() => _showBars = !_showBars);

  Future<void> _share() async {
    final file = await _current.file;
    if (file != null) {
      await Share.shareXFiles([XFile(file.path)]);
    }
  }

  void _openEditor(BuildContext context) {
    if (_current.type == AssetType.video) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Editing is available for photos only')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditScreen(photoId: _current.id)),
    );
  }

  /// Set the current photo as device wallpaper (home / lock / both).
  Future<void> _setAsWallpaper(BuildContext context) async {
    if (_current.type == AssetType.video) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallpaper works with photos only')),
      );
      return;
    }
    final location = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Set as wallpaper'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(ctx, WallpaperManagerFlutter.homeScreen),
            child: const ListTile(
              leading: Icon(Icons.home_outlined),
              title: Text('Home screen'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(ctx, WallpaperManagerFlutter.lockScreen),
            child: const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Lock screen'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(ctx, WallpaperManagerFlutter.bothScreens),
            child: const ListTile(
              leading: Icon(Icons.phone_android_outlined),
              title: Text('Both screens'),
            ),
          ),
        ],
      ),
    );
    if (location == null || !context.mounted) return;
    try {
      final file = await _current.file;
      if (file == null) throw StateError('Could not read photo file');
      final ok =
          await WallpaperManagerFlutter().setWallpaper(file, location);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Wallpaper set' : 'Could not set wallpaper'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not set wallpaper: $e')),
      );
    }
  }

    /// Print the current photo via the system print dialog.
  Future<void> _printPhoto(BuildContext context) async {
    if (_current.type == AssetType.video) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printing works with photos only')),
      );
      return;
    }
    try {
      final bytes = await _current.originBytes;
      if (bytes == null) throw StateError('Could not read photo data');
      final doc = pw.Document();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          build: (ctx) => pw.Center(child: pw.Image(image)),
        ),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: _current.title ?? 'photo.pdf',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not print: $e')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to trash?'),
        content: const Text('The photo stays recoverable in trash for 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final trash = ref.read(trashServiceProvider);
    await trash.moveToTrash([_current.id],
        mediaType: _current.type == AssetType.video ? 'video' : 'image');
    ref.invalidate(photoListProvider);
    ref.invalidate(albumListProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Moved to trash (30 days to restore)'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await trash.restore([_current.id]);
            ref.invalidate(photoListProvider);
            ref.invalidate(albumListProvider);
          },
        ),
      ),
    );
    if (widget.assets.length <= 1) {
      Navigator.of(context).pop();
    } else {
      if (mounted) Navigator.of(context).pop();
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
                    _slideshow ? Icons.pause : Icons.slideshow_outlined,
                    color: Colors.white,
                  ),
                  tooltip: _slideshow ? 'Stop slideshow' : 'Slideshow',
                  onPressed: _toggleSlideshow,
                ),
                IconButton(
                  icon: Icon(
                    isFav ? Icons.star : Icons.star_border,
                    color: isFav ? Colors.amber : Colors.white,
                  ),
                  onPressed: () =>
                      ref.read(favoritesProvider.notifier).toggle(_current.id),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  tooltip: 'Edit',
                  onPressed: () => _openEditor(context),
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
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  tooltip: 'More',
                  onSelected: (value) {
                    switch (value) {
                      case 'wallpaper':
                        _setAsWallpaper(context);
                      case 'print':
                        _printPhoto(context);
                      case 'details':
                        _showDetails(context);
                    }
                  },
                  itemBuilder: (context) => [
                    if (_current.type != AssetType.video)
                      const PopupMenuItem(
                        value: 'wallpaper',
                        child: ListTile(
                          leading: Icon(Icons.wallpaper_outlined),
                          title: Text('Set as wallpaper'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (_current.type != AssetType.video)
                      const PopupMenuItem(
                        value: 'print',
                        child: ListTile(
                          leading: Icon(Icons.print_outlined),
                          title: Text('Print'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'details',
                      child: ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('Details'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          GestureDetector(
            onTap: _toggleBars,
            child: PageView.builder(
          controller: _pageController,
          itemCount: widget.assets.length,
          onPageChanged: (i) {
            // Manual swipes end the slideshow.
            if (_slideshow) _toggleSlideshow();
            setState(() => _currentIndex = i);
            _precacheNeighbors(i);
          },
          itemBuilder: (context, index) {
            final asset = widget.assets[index];
            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Center(
                child: Hero(
                  tag: 'photo_${asset.id}',
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
              ),
            );
          },
        ),
          ),
          // Slideshow controls (visible while playing).
          if (_slideshow)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _slideshowShuffle
                              ? Icons.shuffle_on_outlined
                              : Icons.shuffle_outlined,
                          color: _slideshowShuffle
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                        tooltip: 'Shuffle',
                        onPressed: () => setState(
                          () => _slideshowShuffle = !_slideshowShuffle,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _slideshowRepeat
                              ? Icons.repeat_on_outlined
                              : Icons.repeat_outlined,
                          color: _slideshowRepeat
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                        tooltip: 'Repeat',
                        onPressed: () => setState(
                          () => _slideshowRepeat = !_slideshowRepeat,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.stop_outlined,
                          color: Colors.white,
                        ),
                        tooltip: 'Stop',
                        onPressed: _toggleSlideshow,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
