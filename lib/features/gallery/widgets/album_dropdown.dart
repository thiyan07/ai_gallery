import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../providers/gallery_providers.dart';

/// Album dropdown selector shown in the AppBar title.
class AlbumDropdown extends ConsumerWidget {
  final AsyncValue<List<AssetPathEntity>> albums;
  final String? selectedAlbumId;

  const AlbumDropdown({
    super.key,
    required this.albums,
    required this.selectedAlbumId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return albums.when(
      loading: () => const Text('Loading…'),
      error: (_, __) => const Text('AI Gallery'),
      data: (list) {
        if (list.isEmpty) return const Text('AI Gallery');
        final current = list.firstWhere(
          (album) => album.id == selectedAlbumId,
          orElse: () => list.first,
        );
        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedAlbumId ?? current.id,
            isDense: true,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            onChanged: (albumId) {
              ref.read(selectedAlbumProvider.notifier).select(albumId);
            },
            items: list
                .map(
                  (a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(a.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}
