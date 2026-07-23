import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/selection_provider.dart';
import '../screens/photo_view_screen.dart';

/// A single thumbnail tile in the gallery grid.
class PhotoTile extends ConsumerWidget {
  final AssetEntity asset;
  final List<AssetEntity> allAssets;
  final int index;

  const PhotoTile({
    super.key,
    required this.asset,
    required this.allAssets,
    required this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritesProvider);
    final selection = ref.watch(selectionProvider);
    final selectionNotifier = ref.read(selectionProvider.notifier);

    final isFav = favs.value?.contains(asset.id) ?? false;
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
      onLongPress: () => selectionNotifier.toggle(asset.id),
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
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(isSelected ? 4 : 0),
              child: AssetEntityImage(
                asset,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(300),
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

            // Selection overlay
            if (isSelecting)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.35)
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

            // Video duration badge
            if (asset.type == AssetType.video)
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
}
