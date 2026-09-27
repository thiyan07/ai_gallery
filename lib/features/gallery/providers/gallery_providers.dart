import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../core/di/providers.dart';
import '../../../domain/repositories/photo_repository.dart';
import '../services/trash_service.dart';
import '../services/visibility_service.dart';

/// Recycle bin flows (trash/restore/permanent-delete/purge).
final trashServiceProvider = Provider<TrashService>((ref) {
  final db = ref.watch(appDatabaseProvider).requireValue;
  return TrashService(database: db);
});

/// Archive + Hidden visibility flows.
final visibilityServiceProvider = Provider<VisibilityService>((ref) {
  final db = ref.watch(appDatabaseProvider).requireValue;
  final secure = ref.watch(secureStorageServiceProvider);
  return VisibilityService(database: db, secureStorage: secure);
});

// ─────────────────────────────────────────────
// Gallery sort order (newest/oldest first)
// ─────────────────────────────────────────────

/// True = oldest first, false = newest first. Persisted, applied
/// server-side via MediaStore ordering (correct with pagination).
final photoSortAscendingProvider =
    NotifierProvider<PhotoSortNotifier, bool>(PhotoSortNotifier.new);

class PhotoSortNotifier extends Notifier<bool> {
  @override
  bool build() {
    final storage = ref.watch(storageServiceProvider);
    return storage.isSortAscending();
  }

  void setAscending(bool ascending) {
    state = ascending;
    ref.read(storageServiceProvider).setSortAscending(ascending);
  }

  void toggle() => setAscending(!state);
}

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
    if (!kDebugMode) return;
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
    if (!kDebugMode) return;
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
  /// Maximum photos to keep in memory (prevents unbounded growth on large libraries).
  static const _maxInMemory = 500;
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
    // Re-sort when the user toggles newest/oldest.
    final ascending = ref.watch(photoSortAscendingProvider);

    if (albums.isEmpty) {
      return [];
    }

    _nextPage = 1;

    final albumId = selectedAlbumId ?? albums.first.id;
    final album = await _repo.getAlbumEntityById(albumId);

    // If album is not found, use first album as fallback
    final selectedAlbum = album ?? albums.first;

    // Log for debugging
    _log('Loading album (id: ${selectedAlbum.id})');

    final photos = await _repo.getPhotoEntities(
      album: selectedAlbum,
      pageSize: _pageSize,
      ascending: ascending,
    );

    _log('Loaded ${photos.length} photos from album');
    return _withoutTrashed(photos);
  }

  void _log(String message, {bool isError = false}) {
    if (!kDebugMode) return;
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
          await repository.getPhotoEntities(album: album, page: _nextPage, pageSize: _pageSize, ascending: ref.read(photoSortAscendingProvider));
      _nextPage++;
      _log('Loaded ${more.length} more photos (page $_nextPage)');
      final List<AssetEntity> combined = [...?state.value, ...more];
      // Trim oldest entries if list exceeds max to prevent OOM
      final visible = await _withoutTrashed(combined);
      if (visible.length > _maxInMemory) {
        state = AsyncData(visible.sublist(visible.length - _maxInMemory));
      } else {
        state = AsyncData(visible);
      }
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

  /// Remove trashed, archived, and hidden assets (recycle bin, Archive,
  /// and Hidden sections hide them from the timeline grid).
  Future<List<AssetEntity>> _withoutTrashed(List<AssetEntity> assets) async {
    if (assets.isEmpty) return assets;
    try {
      final trashed = await ref.read(trashServiceProvider).trashedIds();
      final visibility = ref.read(visibilityServiceProvider);
      final archived = await visibility.archivedIds();
      final hidden = await visibility.hiddenIds();
      if (trashed.isEmpty && archived.isEmpty && hidden.isEmpty) {
        return assets;
      }
      return assets
          .where((a) =>
              !trashed.contains(a.id) &&
              !archived.contains(a.id) &&
              !hidden.contains(a.id))
          .toList();
    } catch (_) {
      return assets;
    }
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