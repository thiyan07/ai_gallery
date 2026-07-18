import 'package:photo_manager/photo_manager.dart';

import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';

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
    RequestType type = RequestType.image,
  }) {
    return PhotoManager.getAssetPathList(type: type, onlyAll: false);
  }

  /// Loads photo assets from a given album with pagination.
  Future<List<AssetEntity>> getPhotos(
    AssetPathEntity album, {
    int page = 0,
    int pageSize = 80,
  }) {
    return album.getAssetListPaged(page: page, size: pageSize);
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
}
