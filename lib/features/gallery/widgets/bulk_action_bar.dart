import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/di/providers.dart';
import '../providers/favorites_provider.dart';
import '../providers/gallery_providers.dart';
import '../providers/selection_provider.dart';
import '../services/media_service.dart';

/// Floating bulk-action bar shown at the bottom when photos are selected.
class BulkActionBar extends ConsumerWidget {
  final List<AssetEntity> allAssets;

  const BulkActionBar({super.key, required this.allAssets});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final selectionNotifier = ref.read(selectionProvider.notifier);
    final favsNotifier = ref.read(favoritesProvider.notifier);
    final favs = ref.watch(favoritesProvider).value ?? {};

    if (selection.isEmpty) return const SizedBox.shrink();

    final allFaved = selection.every((id) => favs.contains(id));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Selection count
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${selection.length} selected',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),

              // Favorite / unfavorite
              _ActionButton(
                icon: allFaved ? Icons.star : Icons.star_border,
                label: allFaved ? 'Unfav' : 'Fav',
                color: Colors.amber,
                onTap: () async {
                  for (final id in selection) {
                    await favsNotifier.toggle(id);
                  }
                },
              ),
              const SizedBox(width: 8),

              // Share
              _ActionButton(
                icon: Icons.share_outlined,
                label: 'Share',
                color: Theme.of(context).colorScheme.primary,
                onTap: () async {
                  final selected = allAssets
                      .where((a) => selection.contains(a.id))
                      .toList();
                  final files = <XFile>[];
                  for (final asset in selected) {
                    final file = await asset.file;
                    if (file != null) files.add(XFile(file.path));
                  }
                  if (files.isNotEmpty) {
                    await Share.shareXFiles(files);
                  }
                },
              ),
              const SizedBox(width: 8),

              // Delete
              _ActionButton(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: Theme.of(context).colorScheme.error,
                onTap: () => _confirmDelete(context, ref, selection, selectionNotifier),
              ),
              const SizedBox(width: 8),

              // Close / cancel selection
              _ActionButton(
                icon: Icons.close,
                label: 'Cancel',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                onTap: selectionNotifier.clear,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Set<String> selection,
    SelectionNotifier selectionNotifier,
  ) {
    final count = selection.length;
    final scaffoldContext = context;
    showDialog(
      context: scaffoldContext,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.delete_outline,
          size: 48,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text('Delete $count ${count == 1 ? 'item' : 'items'}?'),
        content: Text(
          'This will permanently delete $count ${count == 1 ? 'photo' : 'photos'} '
          'from your device. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final ids = selection.toList();
              selectionNotifier.clear();
              final deleted = await MediaService.deleteAssets(ids);
              if (deleted > 0) {
                // Clean up DB records for deleted assets so search doesn't return ghosts
                try {
                  final db = await ref.read(appDatabaseProvider.future);
                  for (final id in ids) {
                    await db.database.delete('photo_metadata', where: 'photo_id = ?', whereArgs: [id]);
                    await db.database.delete('embeddings', where: 'photo_id = ?', whereArgs: [id]);
                    await db.database.delete('faces', where: 'photo_id = ?', whereArgs: [id]);
                    await db.database.delete('object_tags', where: 'photo_id = ?', whereArgs: [id]);
                    await db.database.delete('ocr_text', where: 'photo_id = ?', whereArgs: [id]);
                    await db.database.delete('favorites', where: 'asset_id = ?', whereArgs: [id]);
                    await db.database.delete('edit_recipes', where: 'photo_id = ?', whereArgs: [id]);
                    await db.database.delete('analysis_state', where: 'photo_id = ?', whereArgs: [id]);
                  }
                } catch (_) {}
                ref.invalidate(photoListProvider);
                ref.invalidate(albumListProvider);
              }
              if (scaffoldContext.mounted) {
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      deleted > 0
                          ? 'Deleted $deleted ${deleted == 1 ? 'item' : 'items'}'
                          : 'Failed to delete. Check permissions or try again.',
                    ),
                    action: deleted > 0
                        ? SnackBarAction(label: 'OK', onPressed: () {})
                        : null,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
