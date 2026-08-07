import 'package:photo_manager/photo_manager.dart';

import '../../../core/database/daos/photo_metadata_dao.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/photo.dart';

/// Service for scanning gallery images and detecting changes.
class ImageScanner {
  static const _pageSize = 1000;

  ImageScanner({
    required PhotoMetadataDao metadataDao,
    required AppLogger logger,
  })  : _metadataDao = metadataDao,
        _logger = logger;

  final PhotoMetadataDao _metadataDao;
  final AppLogger _logger;

  /// Scans all albums and returns a list of photos that need indexing.
  ///
  /// Returns:
  /// - [newPhotos]: Photos not yet indexed
  /// - [modifiedPhotos]: Photos that have been modified since last index
  /// - [deletedPhotos]: Photos that were indexed but no longer exist
  Future<ScanResult> scan() async {
    _logger.info('Starting image scan');

    final indexedIds = await _metadataDao.getAllIndexedPhotoIds();
    final currentPhotos = <String, Photo>{};
    final newPhotos = <Photo>[];
    final modifiedPhotos = <Photo>[];

    // Get all albums
    final paths = await PhotoManager.getAssetPathList(type: RequestType.image);

    for (final path in paths) {
      int page = 0;
      bool hasMore = true;

      while (hasMore) {
        final assets = await path.getAssetListRange(
          start: page * _pageSize,
          end: (page + 1) * _pageSize,
        );

        if (assets.isEmpty) {
          hasMore = false;
          break;
        }

        for (final asset in assets) {
          final photo = Photo(
            id: asset.id,
            width: asset.width,
            height: asset.height,
            createdAt: asset.createDateTime,
            isVideo: asset.type == AssetType.video,
          );
          currentPhotos[photo.id] = photo;

          if (!indexedIds.contains(photo.id)) {
            newPhotos.add(photo);
          } else {
            // Check if photo has been modified since last index
            final existingMeta = await _metadataDao.getById(photo.id);
            if (existingMeta != null) {
              final DateTime? assetModified = asset.modifiedDateTime;
              if (existingMeta.dateModified != null &&
                  assetModified != null &&
                  assetModified.isAfter(existingMeta.dateModified!)) {
                modifiedPhotos.add(photo);
              }
            }
          }
        }

        page++;
        // Safety limit to prevent infinite loops
        if (page > 10000) {
          _logger.warning('Hit page limit (10000 pages) during scan');
          break;
        }
      }
    }

    // Find deleted photos
    final deletedPhotos = <String>[];
    for (final indexedId in indexedIds) {
      if (!currentPhotos.containsKey(indexedId)) {
        deletedPhotos.add(indexedId);
      }
    }

    _logger.info(
      'Scan complete: ${newPhotos.length} new, ${modifiedPhotos.length} modified, ${deletedPhotos.length} deleted',
    );

    return ScanResult(
      newPhotos: newPhotos,
      modifiedPhotos: modifiedPhotos,
      deletedPhotos: deletedPhotos,
    );
  }
}

/// Result of an image scan.
class ScanResult {
  final List<Photo> newPhotos;
  final List<Photo> modifiedPhotos;
  final List<String> deletedPhotos;

  const ScanResult({
    required this.newPhotos,
    required this.modifiedPhotos,
    required this.deletedPhotos,
  });
}