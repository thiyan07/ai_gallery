import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/media_service.dart';

// ─────────────────────────────────────────────
// Permission
// ─────────────────────────────────────────────

/// Tracks whether the user has granted photo library permission.
final mediaPermissionProvider =
    AsyncNotifierProvider<MediaPermissionNotifier, bool>(
  MediaPermissionNotifier.new,
);

class MediaPermissionNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => MediaService.requestPermission();

  /// Re-request permission (e.g. after user changes settings).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(MediaService.requestPermission);
  }
}

// ─────────────────────────────────────────────
// Album list
// ─────────────────────────────────────────────

/// List of all device albums.
final albumListProvider =
    AsyncNotifierProvider<AlbumListNotifier, List<AssetPathEntity>>(
  AlbumListNotifier.new,
);

class AlbumListNotifier extends AsyncNotifier<List<AssetPathEntity>> {
  @override
  Future<List<AssetPathEntity>> build() async {
    final granted = await ref.watch(mediaPermissionProvider.future);
    if (!granted) return [];
    return MediaService.getAlbums();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => MediaService.getAlbums());
  }
}

// ─────────────────────────────────────────────
// Selected album
// ─────────────────────────────────────────────

/// The album the user is currently viewing (null = "All Photos").
final selectedAlbumProvider =
    NotifierProvider<SelectedAlbumNotifier, AssetPathEntity?>(
  SelectedAlbumNotifier.new,
);

class SelectedAlbumNotifier extends Notifier<AssetPathEntity?> {
  @override
  AssetPathEntity? build() => null;

  void select(AssetPathEntity? album) => state = album;
}

// ─────────────────────────────────────────────
// Photo list for current album
// ─────────────────────────────────────────────

/// Paginated list of AssetEntity for the selected album.
final photoListProvider =
    AsyncNotifierProvider<PhotoListNotifier, List<AssetEntity>>(
  PhotoListNotifier.new,
);

class PhotoListNotifier extends AsyncNotifier<List<AssetEntity>> {
  static const _pageSize = 80;

  @override
  Future<List<AssetEntity>> build() async {
    final albums = await ref.watch(albumListProvider.future);
    final selected = ref.watch(selectedAlbumProvider);

    if (albums.isEmpty) return [];

    final album = selected ?? albums.first;
    return MediaService.getPhotos(album, pageSize: _pageSize);
  }

  /// Load the next page and append results.
  Future<void> loadMore(AssetPathEntity album, int page) async {
    final more =
        await MediaService.getPhotos(album, page: page, pageSize: _pageSize);
    state = AsyncData([...state.value ?? [], ...more]);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
  }
}

// ─────────────────────────────────────────────
// Grid size
// ─────────────────────────────────────────────

/// Persisted grid column count (3–5). Backed by SharedPreferences.
final gridSizeProvider =
    NotifierProvider<GridSizeNotifier, int>(GridSizeNotifier.new);

class GridSizeNotifier extends Notifier<int> {
  @override
  int build() {
    // Default 3 columns; persistence wired in gallery_home_screen via
    // StorageService to keep providers decoupled.
    return 3;
  }

  void setSize(int columns) {
    if (columns >= 2 && columns <= 6) state = columns;
  }
}
