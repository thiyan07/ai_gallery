import 'package:sqflite/sqflite.dart';

import '../../../domain/models/photo_metadata.dart';

/// Data access object for the photo_metadata table.
class PhotoMetadataDao {
  const PhotoMetadataDao(this._db);

  final Database _db;

  /// Inserts or replaces metadata for a photo.
  Future<void> upsert(PhotoMetadata metadata) async {
    await _db.insert(
      'photo_metadata',
      _toRow(metadata),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns metadata for a photo, or null if not found.
  Future<PhotoMetadata?> getById(String photoId) async {
    final rows = await _db.query(
      'photo_metadata',
      where: 'photo_id = ?',
      whereArgs: [photoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Returns metadata for multiple photo IDs in a single query.
  /// Used to fix N+1 query patterns in search result processing.
  Future<Map<String, PhotoMetadata>> getByIds(List<String> photoIds) async {
    if (photoIds.isEmpty) return {};
    final placeholders = photoIds.map((_) => '?').join(',');
    final rows = await _db.query(
      'photo_metadata',
      where: 'photo_id IN ($placeholders)',
      whereArgs: photoIds,
    );
    final map = <String, PhotoMetadata>{};
    for (final row in rows) {
      final meta = _fromRow(row);
      map[meta.photoId] = meta;
    }
    return map;
  }

  /// Returns all photo metadata entries.
  Future<List<PhotoMetadata>> getAll() async {
    final rows = await _db.query('photo_metadata', orderBy: 'indexed_at DESC');
    return rows.map(_fromRow).toList();
  }

  /// Deletes metadata for a photo.
  Future<void> deleteById(String photoId) async {
    await _db.delete(
      'photo_metadata',
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
  }

  /// Deletes a photo and all related records (embeddings, faces, objects,
  /// OCR, favorites, jobs) in a single transaction.
  ///
  /// This prevents orphaned rows when a photo is removed from the device.
  Future<void> deleteCascade(String photoId) async {
    await _db.transaction((txn) async {
      await txn.delete('embeddings', where: 'photo_id = ?', whereArgs: [photoId]);
      await txn.delete('faces', where: 'photo_id = ?', whereArgs: [photoId]);
      await txn.delete('object_tags', where: 'photo_id = ?', whereArgs: [photoId]);
      await txn.delete('ocr_text', where: 'photo_id = ?', whereArgs: [photoId]);
      await txn.delete('favorites', where: 'asset_id = ?', whereArgs: [photoId]);
      await txn.delete('ai_jobs', where: 'photo_id = ?', whereArgs: [photoId]);
      await txn.delete('photo_metadata', where: 'photo_id = ?', whereArgs: [photoId]);
    });
  }

  /// Returns list of all indexed photo IDs.
  Future<Set<String>> getAllIndexedPhotoIds() async {
    final rows = await _db.query(
      'photo_metadata',
      columns: ['photo_id'],
    );
    return rows.map((row) => row['photo_id'] as String).toSet();
  }

  /// Returns IDs of all assets marked as video.
  Future<List<String>> getVideoPhotoIds() async {
    final rows = await _db.query(
      'photo_metadata',
      columns: ['photo_id'],
      where: 'media_type = ?',
      whereArgs: ['video'],
    );
    return rows.map((row) => row['photo_id'] as String).toList();
  }

  /// Find photos near a given latitude/longitude within a radius (in degrees).
  ///
  /// Uses simple bounding-box approximation (suitable for nearby searches).
  /// [radiusDegrees] default ~11km (0.1 degrees ≈ 11.1km at equator).
  Future<Map<String, double>> searchByLocation({
    required double latitude,
    required double longitude,
    double radiusDegrees = 0.1,
  }) async {
    final minLat = latitude - radiusDegrees;
    final maxLat = latitude + radiusDegrees;
    final minLng = longitude - radiusDegrees;
    final maxLng = longitude + radiusDegrees;

    final rows = await _db.rawQuery('''
      SELECT photo_id,
        ABS(latitude - ?) + ABS(longitude - ?) as distance
      FROM photo_metadata
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL
        AND latitude BETWEEN ? AND ?
        AND longitude BETWEEN ? AND ?
      ORDER BY distance ASC
    ''', [latitude, longitude, minLat, maxLat, minLng, maxLng]);

    // Normalize distances to 0-1 score (closer = higher score)
    if (rows.isEmpty) return {};
    final maxDist = (rows.last['distance'] as num).toDouble();
    if (maxDist <= 0) {
      return {for (var row in rows) row['photo_id'] as String: 1.0};
    }
    return {
      for (var row in rows)
        row['photo_id'] as String:
            1.0 - ((row['distance'] as num).toDouble() / (maxDist * 2)),
    };
  }

  Map<String, Object?> _toRow(PhotoMetadata metadata) => {
        'photo_id': metadata.photoId,
        'width': metadata.width,
        'height': metadata.height,
        'file_size_bytes': metadata.fileSizeBytes,
        'mime_type': metadata.mimeType,
        'date_created': metadata.dateCreated?.toIso8601String(),
        'date_modified': metadata.dateModified?.toIso8601String(),
        'camera_make': metadata.cameraMake,
        'camera_model': metadata.cameraModel,
        'iso': metadata.iso,
        'shutter_speed': metadata.shutterSpeed,
        'aperture': metadata.aperture,
        'latitude': metadata.latitude,
        'longitude': metadata.longitude,
        'orientation': metadata.orientation,
        'dominant_color': metadata.dominantColor,
        'average_color': metadata.averageColor,
        'brightness': metadata.brightness,
        'contrast': metadata.contrast,
        'blur_score': metadata.blurScore,
        'quality_score': metadata.qualityScore,
        'indexed_at': metadata.indexedAt.toIso8601String(),
        'album_id': metadata.albumId,
        'folder_path': metadata.folderPath,
        'media_type': metadata.mediaType,
        'duration_seconds': metadata.durationSeconds,
        'ocr_status': metadata.ocrStatus.index,
        'ocr_model_version': metadata.ocrModelVersion,
        'face_status': metadata.faceStatus.index,
        'face_model_version': metadata.faceModelVersion,
      };

  PhotoMetadata _fromRow(Map<String, Object?> row) {
    return PhotoMetadata(
      photoId: row['photo_id'] as String,
      width: row['width'] as int,
      height: row['height'] as int,
      fileSizeBytes: row['file_size_bytes'] as int,
      mimeType: row['mime_type'] as String?,
      dateCreated: row['date_created'] != null
          ? DateTime.parse(row['date_created'] as String)
          : null,
      dateModified: row['date_modified'] != null
          ? DateTime.parse(row['date_modified'] as String)
          : null,
      cameraMake: row['camera_make'] as String?,
      cameraModel: row['camera_model'] as String?,
      iso: row['iso'] as int?,
      shutterSpeed: row['shutter_speed'] as double?,
      aperture: row['aperture'] as double?,
      latitude: row['latitude'] as double?,
      longitude: row['longitude'] as double?,
      orientation: row['orientation'] as int,
      dominantColor: row['dominant_color'] as int?,
      averageColor: row['average_color'] as int?,
      brightness: row['brightness'] as double?,
      contrast: row['contrast'] as double?,
      blurScore: row['blur_score'] as double?,
      qualityScore: row['quality_score'] as double?,
      indexedAt: DateTime.parse(row['indexed_at'] as String),
      albumId: row['album_id'] as String?,
      folderPath: row['folder_path'] as String?,
      mediaType: row['media_type'] as String?,
      durationSeconds: row['duration_seconds'] as int? ?? 0,
      ocrStatus: (row['ocr_status'] as int?)?.toOcrStatus() ?? OcrStatus.notProcessed,
      ocrModelVersion: row['ocr_model_version'] as String?,
      faceStatus: (row['face_status'] as int?)?.toFaceStatus() ?? FaceStatus.notProcessed,
      faceModelVersion: row['face_model_version'] as String?,
    );
  }
}
