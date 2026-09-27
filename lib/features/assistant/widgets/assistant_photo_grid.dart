import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// Displays a grid of photo thumbnails from device assets.
///
/// Resolves photo IDs to AssetEntity and renders using AssetEntityImage,
/// matching the pattern used throughout the gallery (ThumbnailSize.square(300)).
class AssistantPhotoGrid extends StatefulWidget {
  final List<String> photoIds;
  final VoidCallback? onTap;
  final int maxDisplay;
  final double height;

  const AssistantPhotoGrid({
    super.key,
    required this.photoIds,
    this.onTap,
    this.maxDisplay = 4,
    this.height = 80,
  });

  @override
  State<AssistantPhotoGrid> createState() => _AssistantPhotoGridState();
}

class _AssistantPhotoGridState extends State<AssistantPhotoGrid> {
  final Map<String, AssetEntity?> _assetCache = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  @override
  void didUpdateWidget(AssistantPhotoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoIds != widget.photoIds) {
      _loadAssets();
    }
  }

  Future<void> _loadAssets() async {
    setState(() => _isLoading = true);

    final toLoad = widget.photoIds
        .where((id) => !_assetCache.containsKey(id))
        .toList();

    // Load assets in parallel (batch of up to 20)
    final futures = toLoad.take(20).map((id) async {
      final asset = await AssetEntity.fromId(id);
      _assetCache[id] = asset;
    });

    await Future.wait(futures);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayCount = widget.photoIds.length.clamp(0, widget.maxDisplay);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerLow,
        ),
        child: _isLoading
            ? Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    for (int i = 0; i < displayCount; i++)
                      _buildThumbnail(theme, widget.photoIds[i], i),
                    if (widget.photoIds.length > widget.maxDisplay)
                      _buildOverflowBadge(theme),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildThumbnail(ThemeData theme, String photoId, int index) {
    final asset = _assetCache[photoId];

    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
        ),
        clipBehavior: Clip.antiAlias,
        child: asset != null
            ? AssetEntityImage(
                asset,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(300),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
              )
            : _buildPlaceholder(theme),
      ),
    );
  }

  Widget _buildOverflowBadge(ThemeData theme) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Center(
          child: Text(
            '+${widget.photoIds.length - widget.maxDisplay}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Icon(
        Icons.photo,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
