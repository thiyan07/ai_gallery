import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/core/utils/thumbnail_utils.dart';
import 'package:ai_gallery/features/gallery/providers/gallery_providers.dart';
import 'package:ai_gallery/features/gallery/screens/photo_view_screen.dart';

/// Archived photos: hidden from the timeline grid but still visible in
/// albums and search results. Unarchive from here.
class ArchivedScreen extends ConsumerStatefulWidget {
  const ArchivedScreen({super.key});

  @override
  ConsumerState<ArchivedScreen> createState() => _ArchivedScreenState();
}

class _ArchivedScreenState extends ConsumerState<ArchivedScreen> {
  List<String> _ids = [];
  Map<String, AssetEntity> _assets = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ids =
        await ref.read(visibilityServiceProvider).archivedIds();
    // Drop archived items that were trashed since (trash wins).
    final trashed = await ref.read(trashServiceProvider).trashedIds();
    final live = ids.where((id) => !trashed.contains(id)).toList();
    final repo = ref.read(photoRepositoryProvider);
    final assets = await repo.getAssetsByIds(live);
    if (!mounted) return;
    setState(() {
      _ids = live;
      _assets = {for (final a in assets) a.id: a};
      _loading = false;
    });
  }

  Future<void> _unarchive(String id) async {
    await ref.read(visibilityServiceProvider).unhide(id);
    ref.invalidate(photoListProvider);
    await _load();
  }

  Future<void> _openViewer(String id) async {
    final asset = _assets[id];
    if (asset == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewScreen(assets: [asset], initialIndex: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archived')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ids.isEmpty
              ? const Center(
                  child: Text('Nothing archived.\nArchive photos to declutter your timeline.'),
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
                  itemCount: _ids.length,
                  itemBuilder: (context, index) {
                    final id = _ids[index];
                    final asset = _assets[id];
                    return RepaintBoundary(
                      child: GestureDetector(
                        onTap: () => _openViewer(id),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (asset != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AssetEntityImage(
                                  asset,
                                  isOriginal: false,
                                  thumbnailSize: ThumbnailSizes.forGrid(
                                      context, 3,
                                      spacing: 4),
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              const Center(
                                child: Icon(Icons.image_not_supported),
                              ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: _CircleAction(
                                icon: Icons.unarchive_outlined,
                                tooltip: 'Unarchive',
                                onTap: () => _unarchive(id),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
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
