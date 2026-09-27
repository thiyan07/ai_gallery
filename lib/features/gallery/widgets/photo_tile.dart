import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/di/providers.dart';
import '../../editing/providers/edited_photo_providers.dart';
import '../../editing/screens/edit_screen.dart';
import '../providers/favorites_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/gallery_providers.dart';
import '../services/media_service.dart';
import '../screens/photo_view_screen.dart';

/// A single thumbnail tile in the gallery grid.
class PhotoTile extends ConsumerWidget {
  final AssetEntity asset;
  final List<AssetEntity> allAssets;
  final int index;

  /// Decoded thumbnail resolution. Sized by the parent grid via
  /// [ThumbnailSizes.forGrid] so small tiles don't over-decode.
  final ThumbnailSize thumbnailSize;

  const PhotoTile({
    super.key,
    required this.asset,
    required this.allAssets,
    required this.index,
    this.thumbnailSize = const ThumbnailSize.square(300),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fix #4: Use select to only rebuild when THIS asset's favorite status changes,
    // not when any favorite changes (previously rebuilt all 500 tiles on toggle).
    final isFav = ref.watch(favoritesProvider.select((v) => v.value?.contains(asset.id) ?? false));
    final selection = ref.watch(selectionProvider);
    final selectionNotifier = ref.read(selectionProvider.notifier);
    final isEdited = ref.watch(editedPhotoIdsStreamProvider.select((v) => v.value?.contains(asset.id) ?? false));

    final isSelected = selection.contains(asset.id);
    final isSelecting = selection.isNotEmpty;

    return GestureDetector(
      onTap: () {
        if (isSelecting) {
          selectionNotifier.toggle(asset.id);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PhotoViewScreen(assets: allAssets, initialIndex: index),
            ),
          );
        }
      },
      onLongPress: isSelecting
          ? () => selectionNotifier.toggle(asset.id)
          : () => _showContextMenu(
              context, ref, isFav, selectionNotifier, isSelecting),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                )
              : null,
          borderRadius: BorderRadius.circular(isSelected ? 6 : 0),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail (Hero-matched with the full-screen viewer)
            ClipRRect(
              borderRadius: BorderRadius.circular(isSelected ? 4 : 0),
              child: Hero(
                tag: 'photo_${asset.id}',
                child: AssetEntityImage(
                  asset,
                  isOriginal: false,
                  thumbnailSize: thumbnailSize,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),

            // Selection overlay
            if (isSelecting)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(isSelected ? 4 : 0),
                ),
              ),

            // Checkmark (selection mode)
            if (isSelecting)
              Positioned(
                top: 6,
                left: 6,
                child: AnimatedScale(
                  scale: isSelected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // Favorite star icon
            if (isFav && !isSelecting)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.star, size: 14, color: Colors.amber),
                ),
              ),

            // Edit badge (top-right for photos)
            if (isEdited && !isSelecting && asset.type != AssetType.video)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.edit,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),

            // Video duration badge + play icon
            if (asset.type == AssetType.video) ...[
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(asset.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    bool isFav,
    SelectionNotifier selectionNotifier,
    bool isSelecting,
  ) {
    HapticFeedback.mediumImpact();
    final favoritesNotifier = ref.read(favoritesProvider.notifier);
    final scaffoldContext = context;

    showModalBottomSheet(
      context: scaffoldContext,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Asset preview header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AssetEntityImage(
                      asset,
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(80),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: Colors.grey[200],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.type == AssetType.video ? 'Video' : 'Photo',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        Text(
                          _formatDate(asset.createDateTime),
                          style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                isFav ? Icons.star : Icons.star_border,
                color: isFav ? Colors.amber : null,
              ),
              title: Text(isFav ? 'Remove from favorites' : 'Add to favorites'),
              onTap: () {
                Navigator.pop(sheetContext);
                HapticFeedback.lightImpact();
                favoritesNotifier.toggle(asset.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_box_outline_blank),
              title: const Text('Select'),
              onTap: () {
                Navigator.pop(sheetContext);
                selectionNotifier.toggle(asset.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              subtitle: const Text('Hide from timeline, keep in search'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(visibilityServiceProvider).archive(asset.id);
                ref.invalidate(photoListProvider);
                if (scaffoldContext.mounted) {
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    const SnackBar(content: Text('Archived')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Hide'),
              subtitle: const Text('PIN-protected hidden section'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(visibilityServiceProvider).hide(asset.id);
                ref.invalidate(photoListProvider);
                ref.invalidate(albumListProvider);
                if (scaffoldContext.mounted) {
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    const SnackBar(content: Text('Moved to Hidden')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              enabled: asset.type != AssetType.video,
              onTap: () {
                Navigator.pop(sheetContext);
                if (asset.type == AssetType.video) {
                  if (scaffoldContext.mounted) {
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      const SnackBar(content: Text('Editing is available for photos only')),
                    );
                  }
                  return;
                }
                Navigator.of(scaffoldContext).push(
                  MaterialPageRoute(builder: (_) => EditScreen(photoId: asset.id)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final file = await asset.file;
                if (file != null && scaffoldContext.mounted) {
                  await Share.shareXFiles([XFile(file.path)]);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(sheetContext).colorScheme.error),
              title: Text('Move to trash', style: TextStyle(color: Theme.of(sheetContext).colorScheme.error)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await showDialog<bool>(
                  context: scaffoldContext,
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
                await trash.moveToTrash([asset.id],
                    mediaType: asset.type == AssetType.video ? 'video' : 'image');
                ref.invalidate(photoListProvider);
                ref.invalidate(albumListProvider);
                if (!scaffoldContext.mounted) return;
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                  SnackBar(
                    content: const Text('Moved to trash (30 days to restore)'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () async {
                        await trash.restore([asset.id]);
                        ref.invalidate(photoListProvider);
                        ref.invalidate(albumListProvider);
                      },
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Details'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(scaffoldContext).push(
                  MaterialPageRoute(
                    builder: (_) => PhotoViewScreen(
                      assets: [asset],
                      initialIndex: 0,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month]} ${date.day}, ${date.year}  '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
