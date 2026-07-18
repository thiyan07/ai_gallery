import 'package:photo_manager/photo_manager.dart';

import '../../domain/models/album.dart';
import '../../domain/models/photo.dart';

/// Maps [AssetEntity] from photo_manager to domain [Photo] models.
class PhotoMapper {
  const PhotoMapper();

  /// Converts a device asset to a domain [Photo].
  Photo fromAsset(AssetEntity asset, {String? albumId, bool isFavorite = false}) {
    return Photo(
      id: asset.id,
      albumId: albumId,
      width: asset.width,
      height: asset.height,
      createdAt: asset.createDateTime,
      isVideo: asset.type == AssetType.video,
      durationSeconds: asset.duration,
      isFavorite: isFavorite,
    );
  }

  /// Converts a list of assets to domain photos.
  List<Photo> fromAssets(
    List<AssetEntity> assets, {
    String? albumId,
    Set<String> favoriteIds = const {},
  }) {
    return assets
        .map(
          (a) => fromAsset(
            a,
            albumId: albumId,
            isFavorite: favoriteIds.contains(a.id),
          ),
        )
        .toList();
  }
}

/// Maps [AssetPathEntity] from photo_manager to domain [Album] models.
class AlbumMapper {
  const AlbumMapper();

  /// Converts a device album path to a domain [Album].
  Future<Album> fromAssetPath(AssetPathEntity path) async {
    final count = await path.assetCountAsync;
    return Album(
      id: path.id,
      name: path.name,
      assetCount: count,
      isAllPhotos: path.isAll,
    );
  }

  /// Converts a list of album paths to domain albums.
  Future<List<Album>> fromAssetPaths(List<AssetPathEntity> paths) async {
    final albums = <Album>[];
    for (final path in paths) {
      albums.add(await fromAssetPath(path));
    }
    return albums;
  }
}
