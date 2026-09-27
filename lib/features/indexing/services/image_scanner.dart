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
    final currentModified = <String, DateTime?>{};
    final newPhotos = <Photo>[];
    final modifiedPhotos = <Photo>[];

    // Get all albums (photos + videos)
    final paths = await PhotoManager.getAssetPathList(type: RequestType.common);

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
          );
          currentPhotos[photo.id] = photo;
          currentModified[photo.id] = asset.modifiedDateTime;

          if (!indexedIds.contains(photo.id)) {
            newPhotos.add(photo);
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

    // Batch modified check: fetch existing metas in chunks (avoid N× sequential queries)
    // SQLite IN limit ~900, chunk it.
    const batchSize = 900;
    final existingIds = currentPhotos.keys.where(indexedIds.contains).toList();
    if (existingIds.isNotEmpty) {
      for (int i = 0; i < existingIds.length; i += batchSize) {
        final chunk = existingIds.sublist(i, (i + batchSize).clamp(0, existingIds.length));
        final metaMap = await _metadataDao.getByIds(chunk);
        for (final id in chunk) {
          final meta = metaMap[id];
          final assetModified = currentModified[id];
          if (meta != null && meta.dateModified != null && assetModified != null && assetModified.isAfter(meta.dateModified!)) {
            final p = currentPhotos[id];
            if (p != null) modifiedPhotos.add(p);
          }
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