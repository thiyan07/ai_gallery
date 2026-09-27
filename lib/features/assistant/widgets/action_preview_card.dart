import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../models/gallery_action.dart';
import '../services/tool_executor.dart';

/// Rich action preview card shown before executing an action.
///
/// Displays a photo grid preview, action description, and confirm/cancel buttons.
/// Replaces the plain AlertDialog for write actions.
class ActionPreviewCard extends StatefulWidget {
  final TrackedAction tracked;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const ActionPreviewCard({
    super.key,
    required this.tracked,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<ActionPreviewCard> createState() => _ActionPreviewCardState();
}

class _ActionPreviewCardState extends State<ActionPreviewCard> {
  final Map<String, AssetEntity?> _assetCache = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final photoIds = widget.tracked.parameters['photoIds'] as List<String>? ?? [];
    for (final id in photoIds.take(6)) {
      if (!_assetCache.containsKey(id)) {
        _assetCache[id] = await AssetEntity.fromId(id);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracked = widget.tracked;
    final photoIds = tracked.parameters['photoIds'] as List<String>? ?? [];
    final isDestructive = tracked.isDestructive;
    final maxPreview = 6;
    final previewCount = photoIds.length.clamp(0, maxPreview);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    isDestructive ? Icons.warning_amber_rounded : Icons.photo_library_outlined,
                    color: isDestructive ? Colors.orange : theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _getTitle(tracked),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                _getDescription(tracked),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              // Photo preview grid
              if (photoIds.isNotEmpty) ...[
                _isLoading
                    ? const SizedBox(
                        height: 80,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : SizedBox(
                        height: 80,
                        child: Row(
                          children: [
                            for (int i = 0; i < previewCount; i++)
                              _buildThumbnail(theme, photoIds[i]),
                            if (photoIds.length > maxPreview)
                              _buildOverflowBadge(theme, photoIds.length - maxPreview),
                          ],
                        ),
                      ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    '${photoIds.length} photo${photoIds.length == 1 ? '' : 's'} selected',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Destructive warning
              if (isDestructive) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This action cannot be undone.',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: widget.onConfirm,
                    style: isDestructive
                        ? FilledButton.styleFrom(backgroundColor: Colors.orange)
                        : null,
                    child: Text(_getButtonText(tracked)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(ThemeData theme, String photoId) {
    final asset = _assetCache[photoId];
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: asset != null
            ? AssetEntityImage(
                asset,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(200),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
              )
            : _buildPlaceholder(theme),
      ),
    );
  }

  Widget _buildOverflowBadge(ThemeData theme, int overflow) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            '+$overflow',
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
      child: const Icon(Icons.photo, size: 16),
    );
  }

  String _getTitle(TrackedAction tracked) {
    switch (tracked.toolName) {
      case 'delete_photos':
        return 'Delete Photos';
      case 'add_favorites':
        return 'Add to Favorites';
      case 'remove_favorites':
        return 'Remove from Favorites';
      case 'create_album':
        return 'Create Album';
      case 'create_memory':
        return 'Create Memory';
      default:
        return 'Confirm Action';
    }
  }

  String _getDescription(TrackedAction tracked) {
    final count = (tracked.parameters['photoIds'] as List?)?.length ?? 0;
    switch (tracked.toolName) {
      case 'delete_photos':
        return 'Permanently delete $count photo${count == 1 ? '' : 's'} from your gallery.';
      case 'add_favorites':
        return 'Add $count photo${count == 1 ? '' : 's'} to your favorites.';
      case 'remove_favorites':
        return 'Remove $count photo${count == 1 ? '' : 's'} from favorites.';
      case 'create_album':
        final title = tracked.parameters['title'] as String? ?? 'Untitled';
        return 'Create album "$title" with $count photo${count == 1 ? '' : 's'}.';
      case 'create_memory':
        final title = tracked.parameters['memoryTitle'] as String? ?? 'My Memory';
        return 'Create memory "$title" with $count photo${count == 1 ? '' : 's'}.';
      default:
        return tracked.description;
    }
  }

  String _getButtonText(TrackedAction tracked) {
    switch (tracked.toolName) {
      case 'delete_photos':
        return 'Delete';
      case 'add_favorites':
        return 'Add';
      case 'remove_favorites':
        return 'Remove';
      case 'create_album':
        return 'Create';
      case 'create_memory':
        return 'Create';
      default:
        return 'Confirm';
    }
  }
}
