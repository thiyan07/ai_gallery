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

  /// Returns list of all indexed photo IDs.
  Future<Set<String>> getAllIndexedPhotoIds() async {
    final rows = await _db.query(
      'photo_metadata',
      columns: ['photo_id'],
    );
    return rows.map((row) => row['photo_id'] as String).toSet();
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
    );
  }
}
