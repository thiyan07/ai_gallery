import 'package:photo_manager/photo_manager.dart';

/// Service to interact with the device media library via photo_manager.
class MediaService {
  /// Requests photo library permission.
  /// Returns true if access is granted (full or limited).
  static Future<bool> requestPermission() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: true,
        ),
      ),
    );
    return ps.isAuth || ps == PermissionState.limited;
  }

  /// Returns the current permission state without prompting.
  static Future<PermissionState> getPermissionState() async {
    return PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: true,
        ),
      ),
    );
  }

  /// Opens the system settings page for the app (for permission recovery).
  static Future<void> openSettings() async {
    await PhotoManager.openSetting();
  }

  /// Loads all albums (AssetPathEntity) from the device.
  /// [type] — filter by image, video, or both.
  static Future<List<AssetPathEntity>> getAlbums({
    RequestType type = RequestType.image,
  }) async {
    return PhotoManager.getAssetPathList(
      type: type,
      onlyAll: false,
    );
  }

  /// Loads photo assets from a given album with pagination support.
  static Future<List<AssetEntity>> getPhotos(
    AssetPathEntity album, {
    int page = 0,
    int pageSize = 80,
  }) async {
    return album.getAssetListPaged(page: page, size: pageSize);
  }

  /// Fetches a single AssetEntity by its id string.
  static Future<AssetEntity?> getById(String id) async {
    return AssetEntity.fromId(id);
  }
}
