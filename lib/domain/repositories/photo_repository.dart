import 'package:photo_manager/photo_manager.dart';
import 'dart:typed_data';

import '../models/album.dart';
import '../models/photo.dart';

/// Repository for accessing device photos and albums.
abstract class PhotoRepository {
  /// Requests photo library permission.
  Future<bool> requestPermission();

  /// Returns the current permission state.
  Future<PermissionState> getPermissionState();

  /// Opens system settings for permission recovery.
  Future<void> openSettings();

  /// Returns all albums on the device.
  Future<List<Album>> getAlbums();

  /// Returns paginated photos for an album.
  Future<List<Photo>> getPhotos({
    required String albumId,
    int page = 0,
    int pageSize = 80,
    Set<String> favoriteIds = const {},
  });

  /// Returns the underlying [AssetPathEntity] list for UI compatibility.
  Future<List<AssetPathEntity>> getAlbumEntities();

  /// Returns underlying [AssetEntity] list for UI compatibility.
  Future<List<AssetEntity>> getPhotoEntities({
    required AssetPathEntity album,
    int page = 0,
    int pageSize = 80,
    bool ascending = false,
  });

  /// Resolves an album entity by id.
  Future<AssetPathEntity?> getAlbumEntityById(String id);

  /// Fetches a single photo by id.
  Future<Photo?> getById(String id);

  /// Fetches raw image bytes for an asset by id.
  Future<Uint8List?> getImageBytes(String assetId);

  /// Fetches multiple assets by their IDs.
  Future<List<AssetEntity>> getAssetsByIds(List<String> ids);
}
