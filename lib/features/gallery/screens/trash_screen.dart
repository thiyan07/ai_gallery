import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:ai_gallery/core/database/daos/trash_dao.dart';
import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/core/utils/thumbnail_utils.dart';
import 'package:ai_gallery/features/gallery/providers/gallery_providers.dart';

/// Recycle bin: trashed photos stay recoverable for 30 days, then are
/// permanently deleted automatically.
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  List<TrashEntry> _entries = [];
  Map<String, AssetEntity> _assets = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final trash = ref.read(trashServiceProvider);
    // Expired items are permanently deleted on every trash visit.
    await trash.purgeExpired();
    final entries = await trash.entries();
    final repo = ref.read(photoRepositoryProvider);
    final assets = await repo.getAssetsByIds(entries.map((e) => e.assetId).toList());
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _assets = {for (final a in assets) a.id: a};
      _loading = false;
    });
    ref.invalidate(photoListProvider);
    ref.invalidate(albumListProvider);
  }

  Future<void> _restore(TrashEntry entry) async {
    await ref.read(trashServiceProvider).restore([entry.assetId]);
    ref.invalidate(photoListProvider);
    ref.invalidate(albumListProvider);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo restored')),
      );
    }
  }

  Future<void> _deleteForever(TrashEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(trashServiceProvider).deletePermanently([entry.assetId]);
    ref.invalidate(photoListProvider);
    ref.invalidate(albumListProvider);
    await _load();
  }

  Future<void> _emptyTrash() async {
    if (_entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty trash?'),
        content: Text(
          'Permanently delete ${_entries.length} photos? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(trashServiceProvider).emptyTrash();
    ref.invalidate(photoListProvider);
    ref.invalidate(albumListProvider);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (_entries.isNotEmpty)
            TextButton(
              onPressed: _emptyTrash,
              child: const Text('Empty trash'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 64,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text('Trash is empty'),
                      const SizedBox(height: 8),
                      Text(
                        'Deleted photos stay here for 30 days.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  cacheExtent: 800,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final asset = _assets[entry.assetId];
                    return _TrashTile(
                      entry: entry,
                      asset: asset,
                      thumbnailSize:
                          ThumbnailSizes.forGrid(context, 3, spacing: 4),
                      onRestore: () => _restore(entry),
                      onDelete: () => _deleteForever(entry),
                    );
                  },
                ),
    );
  }
}

class _TrashTile extends StatelessWidget {
  const _TrashTile({
    required this.entry,
    required this.asset,
    required this.thumbnailSize,
    required this.onRestore,
    required this.onDelete,
  });

  final TrashEntry entry;
  final AssetEntity? asset;
  final ThumbnailSize thumbnailSize;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final days = entry.daysLeft();
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AssetEntityImage(
                  asset!,
                  isOriginal: false,
                  thumbnailSize: thumbnailSize,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              )
            else
              const Center(child: Icon(Icons.image_not_supported_outlined)),
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${days}d left',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TileButton(
                    icon: Icons.restore,
                    tooltip: 'Restore',
                    onTap: onRestore,
                  ),
                  _TileButton(
                    icon: Icons.delete_forever_outlined,
                    tooltip: 'Delete forever',
                    onTap: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileButton extends StatelessWidget {
  const _TileButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
