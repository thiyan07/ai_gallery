import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import 'package:photo_manager/src/filter/classical/filter_option_group.dart';
import 'package:photo_manager/src/filter/classical/filter_options.dart';

/// Data source for device media library access via photo_manager.
class DeviceMediaDataSource {
  DeviceMediaDataSource({AppLogger? logger}) : _logger = logger;

  final AppLogger? _logger;

  /// Requests photo library permission.
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: true,
        ),
      ),
    );
    final granted = state.isAuth || state == PermissionState.limited;
    _logger?.info('Media permission: ${granted ? "granted" : "denied"}');
    return granted;
  }

  /// Returns the current permission state without prompting.
  Future<PermissionState> getPermissionState() {
    return PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: true,
        ),
      ),
    );
  }

  /// Opens the system settings page for the app.
  Future<void> openSettings() => PhotoManager.openSetting();

  /// Loads all albums from the device.
  Future<List<AssetPathEntity>> getAlbums({
    RequestType type = RequestType.common,
  }) {
    return PhotoManager.getAssetPathList(type: type, onlyAll: false);
  }

  /// Loads all albums with sorting by creation date (most recent first).
  Future<List<AssetPathEntity>> getAlbumsSortedByDate({
    RequestType type = RequestType.common,
    bool ascending = false,
  }) {
    final filterOption = FilterOptionGroup(
      orders: [
        OrderOption(
          type: OrderOptionType.createDate,
          asc: ascending,
        ),
      ],
    );
    return PhotoManager.getAssetPathList(
      type: type,
      onlyAll: false,
      filterOption: filterOption,
    );
  }

  /// Loads photo assets from a given album with pagination, sorted by creation date.
  Future<List<AssetEntity>> getPhotos(
    AssetPathEntity album, {
    int page = 0,
    int pageSize = 80,
    bool ascending = false,
  }) async {
    // Sort by creation date; direction is user-configurable (Aves-style).
    final filterOption = FilterOptionGroup(
      orders: [
        OrderOption(
          type: OrderOptionType.createDate,
          asc: ascending,
        ),
      ],
    );
    // Recreate the album with the filter option to apply sorting
    final albumWithFilter = await AssetPathEntity.fromId(
      album.id,
      filterOption: filterOption,
      type: album.type,
      albumType: album.albumType,
    );
    return albumWithFilter.getAssetListPaged(page: page, size: pageSize);
  }

  /// Resolves an album path by id.
  Future<AssetPathEntity?> getAlbumById(String id) async {
    final albums = await getAlbums();
    for (final album in albums) {
      if (album.id == id) return album;
    }
    return null;
  }

  /// Fetches a single asset by id.
  Future<AssetEntity?> getById(String id) => AssetEntity.fromId(id);

  /// Resolves album for an asset path entity, throwing if not found.
  Future<AssetPathEntity> requireAlbum(String albumId) async {
    final album = await getAlbumById(albumId);
    if (album == null) {
      throw NotFoundException('Album not found: $albumId');
    }
    return album;
  }

  /// Fetches raw image bytes for an asset by id.
  Future<Uint8List?> getBytes(String assetId) async {
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) return null;
    return asset.originBytes;
  }

  /// Fetches multiple assets by their IDs.
  Future<List<AssetEntity>> getAssetsByIds(List<String> ids) async {
    final assets = <AssetEntity>[];
    for (final id in ids) {
      final asset = await AssetEntity.fromId(id);
      if (asset != null) {
        assets.add(asset);
      }
    }
    return assets;
  }
}
