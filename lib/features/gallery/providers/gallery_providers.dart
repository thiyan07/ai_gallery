import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../core/di/providers.dart';
import '../../../domain/repositories/photo_repository.dart';

// ─────────────────────────────────────────────
// Permission
// ─────────────────────────────────────────────

/// Tracks whether the user has granted photo library permission.
final mediaPermissionProvider =
    AsyncNotifierProvider<MediaPermissionNotifier, bool>(
  MediaPermissionNotifier.new,
);

class MediaPermissionNotifier extends AsyncNotifier<bool> {
  PhotoRepository? _repository;

  PhotoRepository get _repo {
    _repository ??= ref.watch(photoRepositoryProvider);
    return _repository!;
  }

  @override
  Future<bool> build() async {
    try {
      final granted = await _repo.requestPermission();
      _log('Permission status: ${granted ? "granted" : "denied"}');
      return granted;
    } catch (e, stackTrace) {
      _log('Error checking permissions: $e', isError: true);
      _log('Stack trace: $stackTrace', isError: true);
      rethrow;
    }
  }

  /// Re-request permission (e.g. after user changes settings).
  Future<void> refresh() async {
    try {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() => _repo.requestPermission());
    } catch (e, stackTrace) {
      _log('Error refreshing permissions: $e', isError: true);
      _log('Stack trace: $stackTrace', isError: true);
      rethrow;
    }
  }

  void _log(String message, {bool isError = false}) {
    if (isError) {
      debugPrint('🔴 [MediaPermissionNotifier] $message');
    } else {
      debugPrint('🟢 [MediaPermissionNotifier] $message');
    }
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
  PhotoRepository? _repository;

  PhotoRepository get _repo {
    _repository ??= ref.watch(photoRepositoryProvider);
    return _repository!;
  }

  @override
  Future<List<AssetPathEntity>> build() async {
    try {
      final granted = await ref.watch(mediaPermissionProvider.future);
      if (!granted) {
        _log('Permission not granted for album list');
        return [];
      }
      final albums = await _repo.getAlbumEntities();
      _log('Loaded ${albums.length} albums');
      return albums;
    } catch (e, stackTrace) {
      _log('Error loading albums: $e', isError: true);
      _log('Stack trace: $stackTrace', isError: true);
      rethrow;
    }
  }

  Future<void> refresh() async {
    try {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() => _repo.getAlbumEntities());
    } catch (e, stackTrace) {
      _log('Error refreshing albums: $e', isError: true);
      _log('Stack trace: $stackTrace', isError: true);
      rethrow;
    }
  }

  void _log(String message, {bool isError = false}) {
    if (isError) {
      debugPrint('🔴 [AlbumListNotifier] $message');
    } else {
      debugPrint('🟢 [AlbumListNotifier] $message');
    }
  }
}

// ─────────────────────────────────────────────
// Selected album
// ─────────────────────────────────────────────

/// The album the user is currently viewing (null = "All Photos").
final selectedAlbumProvider =
    NotifierProvider<SelectedAlbumNotifier, String?>(
  SelectedAlbumNotifier.new,
);

class SelectedAlbumNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? albumId) => state = albumId;
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
  PhotoRepository? _repository;
  int _nextPage = 1;

  PhotoRepository get _repo {
    _repository ??= ref.watch(photoRepositoryProvider);
    return _repository!;
  }

  @override
  Future<List<AssetEntity>> build() async {
    // Watch selected album and album list - changes to either will rebuild this provider
    final selectedAlbumId = ref.watch(selectedAlbumProvider);
    final albums = await ref.watch(albumListProvider.future);

    if (albums.isEmpty) {
      return [];
    }

    _nextPage = 1;

    final albumId = selectedAlbumId ?? albums.first.id;
    final album = await _repo.getAlbumEntityById(albumId);

    // If album is not found, use first album as fallback
    final selectedAlbum = album ?? albums.first;

    // Log for debugging
    _log('Loading album: ${selectedAlbum.name} (id: ${selectedAlbum.id})');

    final photos = await _repo.getPhotoEntities(
      album: selectedAlbum,
      pageSize: _pageSize,
    );

    _log('Loaded ${photos.length} photos from album');
    return photos;
  }

  void _log(String message, {bool isError = false}) {
    if (isError) {
      debugPrint('🔴 [PhotoListNotifier] $message');
    } else {
      debugPrint('🟢 [PhotoListNotifier] $message');
    }
  }

  /// Load the next page and append results. Uses currently selected album.
  Future<void> loadMore() async {
    if (state.isLoading) return;

    // Read current selected album and album list
    final selectedAlbumId = ref.read(selectedAlbumProvider);
    final albums = ref.read(albumListProvider).value;

    if (albums == null || albums.isEmpty) {
      _log('No albums available for loadMore', isError: true);
      return;
    }

    final albumId = selectedAlbumId ?? albums.first.id;

    try {
      final repository = ref.read(photoRepositoryProvider);
      final album = await repository.getAlbumEntityById(albumId);
      if (album == null) {
        _log('Album not found for ID: $albumId', isError: true);
        return;
      }

      final more =
          await repository.getPhotoEntities(album: album, page: _nextPage, pageSize: _pageSize);
      _nextPage++;
      _log('Loaded ${more.length} more photos (page $_nextPage)');
      state = AsyncData([...state.value ?? [], ...more]);
    } catch (e, stackTrace) {
      _log('Error loading more photos: $e', isError: true);
      _log('Stack trace: $stackTrace', isError: true);
      // Don't rethrow here to avoid breaking infinite scroll
    }
  }

  Future<void> refresh() async {
    _nextPage = 1; // Reset to page 1 on refresh
    ref.invalidateSelf();
  }
}

// ─────────────────────────────────────────────
// Grid size
// ─────────────────────────────────────────────

/// Persisted grid column count (2–6). Backed by SharedPreferences.
final gridSizeProvider =
    NotifierProvider<GridSizeNotifier, int>(GridSizeNotifier.new);

class GridSizeNotifier extends Notifier<int> {
  @override
  int build() {
    // Load from StorageService
    final storage = ref.watch(storageServiceProvider);
    return storage.getGridSize();
  }

  void setSize(int columns) {
    if (columns < 2 || columns > 6) return;
    state = columns;
    final storage = ref.read(storageServiceProvider);
    storage.setGridSize(columns);
  }

  /// Adjust grid size by a delta, respecting bounds
  void adjustBy(int delta) {
    final newSize = (state + delta).clamp(2, 6);
    if (newSize != state) {
      setSize(newSize);
    }
  }
}