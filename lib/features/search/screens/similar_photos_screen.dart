import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_gallery/core/di/providers.dart' hide searchServiceProvider;
import 'package:ai_gallery/features/gallery/providers/gallery_providers.dart';
import 'package:ai_gallery/features/gallery/screens/photo_view_screen.dart';
import 'package:ai_gallery/features/search/providers/search_providers.dart';
import 'package:ai_gallery/features/search/widgets/search_results_grid.dart';

/// Photos visually similar to [photoId], via embedding similarity.
final similarPhotosProvider =
    FutureProvider.family<List<RankedSearchResult>, String>((ref, photoId) async {
  final service = ref.watch(searchServiceProvider);
  return service.searchSimilar(photoId, limit: 20);
});

/// Full-screen view of photos similar to one photo ("more like this").
class SimilarPhotosScreen extends ConsumerWidget {
  const SimilarPhotosScreen({
    super.key,
    required this.photoId,
    this.query = '',
  });

  final String photoId;

  /// Originating query, forwarded so feedback actions keep working.
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gridSize = ref.watch(gridSizeProvider);
    final similarAsync = ref.watch(similarPhotosProvider(photoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Similar photos')),
      body: similarAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (results) {
          if (results.isEmpty) {
            return const Center(
              child: Text('No similar photos found.'),
            );
          }
          return SearchResultsGrid(
            results: results,
            gridSize: gridSize,
            query: query,
            onTap: (result) => _openPhotoView(context, ref, results, result),
          );
        },
      ),
    );
  }

  Future<void> _openPhotoView(
    BuildContext context,
    WidgetRef ref,
    List<RankedSearchResult> results,
    RankedSearchResult tapped,
  ) async {
    final photoIds = results.map((r) => r.photoId).toList();
    final photoRepo = ref.read(photoRepositoryProvider);
    final assets = await photoRepo.getAssetsByIds(photoIds);
    if (!context.mounted || assets.isEmpty) return;
    final initialIndex = assets.indexWhere((a) => a.id == tapped.photoId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewScreen(
          assets: assets,
          initialIndex: initialIndex >= 0 ? initialIndex : 0,
        ),
      ),
    );
  }
}
