import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/core/utils/thumbnail_utils.dart';
import 'package:ai_gallery/domain/models/duplicate_group.dart';
import 'package:ai_gallery/domain/models/photo_metadata.dart';
import 'package:ai_gallery/features/gallery/providers/gallery_providers.dart';
import 'package:ai_gallery/features/gallery/screens/photo_view_screen.dart';

/// Clean-up hub (CleanSweep/Gallery-Cleaner concept, reimplemented):
/// review duplicate groups, blurry shots, and space-hogging files,
/// sending the rejects to trash (recoverable for 30 days).
class CleanupScreen extends ConsumerStatefulWidget {
  const CleanupScreen({super.key});

  @override
  ConsumerState<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends ConsumerState<CleanupScreen> {
  bool _loading = true;
  List<DuplicateGroup> _groups = [];
  List<PhotoMetadata> _blurry = [];
  List<PhotoMetadata> _largest = [];
  Map<String, AssetEntity> _assets = {};
  Map<String, PhotoMetadata> _metaById = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await ref.read(appDatabaseProvider.future);

    final groups = await db.duplicates.getAll();
    final blurryRows = await db.database.rawQuery(
      'SELECT * FROM photo_metadata WHERE blur_score >= 0.6 '
      'ORDER BY blur_score DESC LIMIT 50',
    );
    final largestRows = await db.database.rawQuery(
      'SELECT * FROM photo_metadata WHERE file_size_bytes > 0 '
      'ORDER BY file_size_bytes DESC LIMIT 30',
    );
    final blurry = blurryRows.map(PhotoMetadata.fromMap).toList();
    final largest = largestRows.map(PhotoMetadata.fromMap).toList();

    // Exclude already-trashed items from every section.
    final trashed = await db.trash.trashedIds();
    final liveGroups = groups
        .map((g) => g.copyWith(
              photoIds: g.photoIds.where((id) => !trashed.contains(id)).toList(),
            ))
        .where((g) => g.photoIds.length > 1)
        .toList();
    final liveBlurry =
        blurry.where((m) => !trashed.contains(m.photoId)).toList();
    final liveLargest =
        largest.where((m) => !trashed.contains(m.photoId)).toList();

    final ids = <String>{
      for (final g in liveGroups) ...g.photoIds,
      for (final m in liveBlurry) m.photoId,
      for (final m in liveLargest) m.photoId,
    };
    final repo = ref.read(photoRepositoryProvider);
    final assets = await repo.getAssetsByIds(ids.toList());

    if (!mounted) return;
    setState(() {
      _groups = liveGroups;
      _blurry = liveBlurry;
      _largest = liveLargest;
      _assets = {for (final a in assets) a.id: a};
      _metaById = {
        for (final m in [...liveBlurry, ...liveLargest]) m.photoId: m
      };
      _loading = false;
    });
  }

  Future<void> _trashIds(List<String> ids, String label) async {
    if (ids.isEmpty) return;
    await ref.read(trashServiceProvider).moveToTrash(ids);
    ref.invalidate(photoListProvider);
    ref.invalidate(albumListProvider);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label moved to trash')),
      );
    }
  }

  /// Best photo to keep in a group: highest quality, then largest file.
  String _bestId(DuplicateGroup group) {
    if (group.recommendedKeepId != null &&
        group.photoIds.contains(group.recommendedKeepId)) {
      return group.recommendedKeepId!;
    }
    var best = group.photoIds.first;
    var bestScore = -1.0;
    var bestSize = -1;
    for (final id in group.photoIds) {
      final meta = _metaById[id];
      final score = meta?.qualityScore ?? 0.0;
      final size = meta?.fileSizeBytes ?? 0;
      if (score > bestScore || (score == bestScore && size > bestSize)) {
        best = id;
        bestScore = score;
        bestSize = size;
      }
    }
    return best;
  }

  Future<void> _openViewer(String photoId) async {
    final asset = _assets[photoId];
    if (asset == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewScreen(assets: [asset], initialIndex: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Clean up')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_groups.isEmpty && _blurry.isEmpty && _largest.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      const Text('Nothing to clean up'),
                      const SizedBox(height: 8),
                      Text(
                        'No duplicates, blurry shots, or large files found.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_groups.isNotEmpty) ...[
                      _Header(
                        icon: Icons.copy_outlined,
                        title: 'Duplicates',
                        subtitle:
                            '${_groups.length} groups · keep the best, trash the rest',
                      ),
                      const SizedBox(height: 8),
                      for (final group in _groups)
                        _DuplicateGroupCard(
                          group: group,
                          assets: _assets,
                          bestId: _bestId(group),
                          onOpen: _openViewer,
                          onTrashOne: (id) => _trashIds([id], 'Photo'),
                          onKeepBest: (keep) => _trashIds(
                            group.photoIds.where((id) => id != keep).toList(),
                            '${group.photoIds.length - 1} duplicates',
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                    if (_blurry.isNotEmpty) ...[
                      _Header(
                        icon: Icons.blur_on_outlined,
                        title: 'Blurry shots',
                        subtitle: '${_blurry.length} photos may be out of focus',
                      ),
                      const SizedBox(height: 8),
                      _PhotoRow(
                        ids: _blurry.map((m) => m.photoId).toList(),
                        assets: _assets,
                        metaById: _metaById,
                        badge: (id) {
                          final b = _metaById[id]?.blurScore;
                          return b == null
                              ? null
                              : 'blur ${(b * 100).toInt()}%';
                        },
                        onOpen: _openViewer,
                        onTrash: (id) => _trashIds([id], 'Photo'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_largest.isNotEmpty) ...[
                      _Header(
                        icon: Icons.storage_outlined,
                        title: 'Largest files',
                        subtitle: 'Free up space, biggest first',
                      ),
                      const SizedBox(height: 8),
                      _PhotoRow(
                        ids: _largest.map((m) => m.photoId).toList(),
                        assets: _assets,
                        metaById: _metaById,
                        badge: (id) {
                          final s = _metaById[id]?.fileSizeBytes ?? 0;
                          return _formatBytes(s);
                        },
                        onOpen: _openViewer,
                        onTrash: (id) => _trashIds([id], 'Photo'),
                      ),
                    ],
                  ],
                ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({
    required this.group,
    required this.assets,
    required this.bestId,
    required this.onOpen,
    required this.onTrashOne,
    required this.onKeepBest,
  });

  final DuplicateGroup group;
  final Map<String, AssetEntity> assets;
  final String bestId;
  final void Function(String) onOpen;
  final void Function(String) onTrashOne;
  final void Function(String) onKeepBest;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: group.photoIds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final id = group.photoIds[i];
                  final asset = assets[id];
                  final isBest = id == bestId;
                  return GestureDetector(
                    onTap: () => onOpen(id),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: asset == null
                              ? Container(
                                  width: 96,
                                  height: 96,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Icon(Icons.image_not_supported),
                                )
                              : AssetEntityImage(
                                  asset,
                                  isOriginal: false,
                                  thumbnailSize:
                                      ThumbnailSizes.forGrid(context, 4),
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        if (isBest)
                          const Positioned(
                            top: 4,
                            left: 4,
                            child: _Pill(
                              text: 'KEEP',
                              color: Colors.green,
                            ),
                          ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: _CircleButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Move to trash',
                            onTap: () => onTrashOne(id),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${group.photoIds.length} similar · ${(group.similarity * 100).toInt()}% match',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => onKeepBest(bestId),
                  child: const Text('Keep best, trash rest'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.ids,
    required this.assets,
    required this.metaById,
    required this.badge,
    required this.onOpen,
    required this.onTrash,
  });

  final List<String> ids;
  final Map<String, AssetEntity> assets;
  final Map<String, PhotoMetadata> metaById;
  final String? Function(String) badge;
  final void Function(String) onOpen;
  final void Function(String) onTrash;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ids.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = ids[i];
          final asset = assets[id];
          final label = badge(id);
          return GestureDetector(
            onTap: () => onOpen(id),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: asset == null
                      ? Container(
                          width: 96,
                          height: 120,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.image_not_supported),
                        )
                      : AssetEntityImage(
                          asset,
                          isOriginal: false,
                          thumbnailSize: ThumbnailSizes.forGrid(context, 4),
                          width: 96,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                ),
                if (label != null)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: _Pill(text: label, color: Colors.black54),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _CircleButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Move to trash',
                    onTap: () => onTrash(id),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
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
