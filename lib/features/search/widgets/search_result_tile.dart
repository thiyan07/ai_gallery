import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:ai_gallery/features/search/services/ranking_engine.dart';

/// A single search result tile showing thumbnail and relevance score.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.asset,
    this.onLongPress,
    this.thumbnailSize = const ThumbnailSize.square(300),
  });

  final RankedSearchResult result;
  final VoidCallback onTap;
  final AssetEntity? asset;

  /// Long-press opens the result menu (find similar / not relevant).
  final VoidCallback? onLongPress;

  /// Decoded thumbnail resolution, sized by the parent grid.
  final ThumbnailSize thumbnailSize;

  @override
  Widget build(BuildContext context) {
    final signalLabel = resultSignalLabel(result);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (asset != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Hero(
                  tag: 'photo_${asset!.id}',
                  child: AssetEntityImage(
                    asset!,
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
              )
            else
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primaryContainer,
                      Theme.of(context).colorScheme.secondaryContainer,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.image,
                    size: 32,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${(result.score * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (signalLabel != null)
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    signalLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Short human-readable label for the strongest match signal, e.g.
/// "Object", "Region · dog", "Text", "Person". Null when nothing recorded.
String? resultSignalLabel(RankedSearchResult result) {
  if (result.matchedSignals.isEmpty) return null;
  final signal = result.matchedSignals.first;
  if (signal.startsWith('region:')) {
    return 'Region · ${signal.substring('region:'.length)}';
  }
  return switch (signal) {
    'person' => 'Person',
    'object' => 'Object',
    'ocr' => 'Text',
    'semantic' => 'Match',
    'location' => 'Location',
    'date' => 'Date',
    _ => null,
  };
}
