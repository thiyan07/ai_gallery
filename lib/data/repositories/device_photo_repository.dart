import 'package:photo_manager/photo_manager.dart';
import 'dart:typed_data';

import '../../data/datasources/device_media_datasource.dart';
import '../../data/mappers/photo_mapper.dart';
import '../../domain/models/album.dart';
import '../../domain/models/photo.dart';
import '../../domain/repositories/photo_repository.dart';

/// Device media library implementation of [PhotoRepository].
class DevicePhotoRepository implements PhotoRepository {
  DevicePhotoRepository({
    required DeviceMediaDataSource dataSource,
    PhotoMapper? photoMapper,
    AlbumMapper? albumMapper,
  })  : _dataSource = dataSource,
        _photoMapper = photoMapper ?? const PhotoMapper(),
        _albumMapper = albumMapper ?? const AlbumMapper();

  final DeviceMediaDataSource _dataSource;
  final PhotoMapper _photoMapper;
  final AlbumMapper _albumMapper;

  @override
  Future<bool> requestPermission() => _dataSource.requestPermission();

  @override
  Future<PermissionState> getPermissionState() =>
      _dataSource.getPermissionState();

  @override
  Future<void> openSettings() => _dataSource.openSettings();

  @override
  Future<List<Album>> getAlbums() async {
    final paths = await _dataSource.getAlbums();
    return _albumMapper.fromAssetPaths(paths);
  }

  @override
  Future<List<Photo>> getPhotos({
    required String albumId,
    int page = 0,
    int pageSize = 80,
    Set<String> favoriteIds = const {},
  }) async {
    final album = await _dataSource.requireAlbum(albumId);
    final assets = await _dataSource.getPhotos(album, page: page, pageSize: pageSize);
    return _photoMapper.fromAssets(assets, albumId: albumId, favoriteIds: favoriteIds);
  }

  @override
  Future<List<AssetPathEntity>> getAlbumEntities() => _dataSource.getAlbums();

  @override
  Future<List<AssetEntity>> getPhotoEntities({
    required AssetPathEntity album,
    int page = 0,
    int pageSize = 80,
  }) {
    return _dataSource.getPhotos(album, page: page, pageSize: pageSize);
  }

  @override
  Future<AssetPathEntity?> getAlbumEntityById(String id) =>
      _dataSource.getAlbumById(id);

  @override
  Future<Photo?> getById(String id) async {
    final asset = await _dataSource.getById(id);
    if (asset == null) return null;
    return _photoMapper.fromAsset(asset);
  }

  @override
  Future<Uint8List?> getImageBytes(String assetId) => _dataSource.getBytes(assetId);

  @override
  Future<List<AssetEntity>> getAssetsByIds(List<String> ids) => _dataSource.getAssetsByIds(ids);
}