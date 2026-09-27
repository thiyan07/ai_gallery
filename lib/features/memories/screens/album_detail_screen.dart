import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../../../domain/models/memory/automatic_album.dart';
import '../../gallery/screens/photo_view_screen.dart';

/// Detail screen for an automatic album — shows header info + photo grid.
class AlbumDetailScreen extends ConsumerStatefulWidget {
  final AutomaticAlbum album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  final Map<String, AssetEntity?> _assetCache = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    for (final id in widget.album.photoIds.take(200)) {
      if (!_assetCache.containsKey(id)) {
        _assetCache[id] = await AssetEntity.fromId(id);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final album = widget.album;

    return Scaffold(
      appBar: AppBar(
        title: Text(album.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(theme, album),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(4),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final photoId = album.photoIds[index];
                        final asset = _assetCache[photoId];
                        if (asset == null) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: () => _openPhoto(index),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: AssetEntityImage(
                              asset,
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize.square(300),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: theme.colorScheme.surfaceContainerHigh,
                                child: const Icon(Icons.photo, size: 20),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: album.photoIds.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(ThemeData theme, AutomaticAlbum album) {
    final dateRange =
        '${_formatDate(album.startDate)} — ${_formatDate(album.endDate)}';

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForType(album.type), size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                album.typeLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            album.title,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(dateRange, style: theme.textTheme.bodySmall),
              const SizedBox(width: 16),
              Icon(Icons.photo_library_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('${album.photoCount} photos', style: theme.textTheme.bodySmall),
            ],
          ),
          if (album.locationLabel != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(album.locationLabel!, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _openPhoto(int index) {
    final assets = widget.album.photoIds
        .map((id) => _assetCache[id])
        .whereType<AssetEntity>()
        .toList();
    if (assets.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewScreen(
          assets: assets,
          initialIndex: index.clamp(0, assets.length - 1),
        ),
      ),
    );
  }

  IconData _iconForType(AutomaticAlbumType type) {
    switch (type) {
      case AutomaticAlbumType.bestOfYear:
        return Icons.star;
      case AutomaticAlbumType.monthlyHighlights:
        return Icons.auto_awesome;
      case AutomaticAlbumType.trip:
        return Icons.flight;
      case AutomaticAlbumType.event:
        return Icons.event;
      case AutomaticAlbumType.people:
        return Icons.people;
      case AutomaticAlbumType.seasonal:
        return Icons.wb_sunny;
      case AutomaticAlbumType.recurring:
        return Icons.repeat;
      case AutomaticAlbumType.place:
        return Icons.location_on;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}
