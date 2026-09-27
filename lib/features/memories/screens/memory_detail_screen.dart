import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../../../domain/models/memory/memory.dart';
import '../../gallery/screens/photo_view_screen.dart';

/// Detail screen for a memory — shows header info + photo grid.
class MemoryDetailScreen extends ConsumerStatefulWidget {
  final Memory memory;

  const MemoryDetailScreen({super.key, required this.memory});

  @override
  ConsumerState<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends ConsumerState<MemoryDetailScreen> {
  final Map<String, AssetEntity?> _assetCache = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    for (final id in widget.memory.photoIds.take(200)) {
      if (!_assetCache.containsKey(id)) {
        _assetCache[id] = await AssetEntity.fromId(id);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memory = widget.memory;

    return Scaffold(
      appBar: AppBar(
        title: Text(memory.title),
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
                  child: _buildHeader(theme, memory),
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
                        final photoId = memory.photoIds[index];
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
                      childCount: memory.photoIds.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(ThemeData theme, Memory memory) {
    final dateRange =
        '${_formatDate(memory.startDate)} — ${_formatDate(memory.endDate)}';

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            memory.title,
            style: theme.textTheme.headlineSmall,
          ),
          if (memory.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              memory.subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(dateRange, style: theme.textTheme.bodySmall),
              const SizedBox(width: 16),
              Icon(Icons.photo_library_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('${memory.photoCount} photos', style: theme.textTheme.bodySmall),
            ],
          ),
          if (memory.locationLabel != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(memory.locationLabel!, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _openPhoto(int index) {
    final assets = widget.memory.photoIds
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

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}
