import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/gallery_providers.dart';
import '../providers/favorites_provider.dart';
import '../widgets/photo_tile.dart';

/// Shows only the photos the user has starred.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritesProvider);
    final photos = ref.watch(photoListProvider);
    final gridSize = ref.watch(gridSizeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: [
          favs.when(
            data: (ids) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: Text('${ids.length}'),
                avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: favs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (favoriteIds) {
          if (favoriteIds.isEmpty) {
            return _emptyState(context);
          }

          return photos.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (allPhotos) {
              final favPhotos = allPhotos
                  .where((a) => favoriteIds.contains(a.id))
                  .toList();

              if (favPhotos.isEmpty) {
                return _emptyState(context);
              }

              return GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridSize,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: favPhotos.length,
                itemBuilder: (context, index) => PhotoTile(
                  asset: favPhotos[index],
                  allAssets: favPhotos,
                  index: index,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.star_border_rounded,
            size: 72,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No favorites yet',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap ★ on any photo to add it here.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
