/// Domain model representing metadata extracted from a photo.
enum OcrStatus {
  notProcessed,
  processing,
  completed,
  noText,
  failed,
}

extension OcrStatusExtension on int? {
  OcrStatus toOcrStatus() {
    switch (this) {
      case 0:
        return OcrStatus.notProcessed;
      case 1:
        return OcrStatus.processing;
      case 2:
        return OcrStatus.completed;
      case 3:
        return OcrStatus.noText;
      case 4:
        return OcrStatus.failed;
      default:
        return OcrStatus.notProcessed;
    }
  }
}

enum FaceStatus {
  notProcessed,
  processing,
  completed,
  noFaces,
  failed,
}

extension FaceStatusExtension on int? {
  FaceStatus toFaceStatus() {
    switch (this) {
      case 0:
        return FaceStatus.notProcessed;
      case 1:
        return FaceStatus.processing;
      case 2:
        return FaceStatus.completed;
      case 3:
        return FaceStatus.noFaces;
      case 4:
        return FaceStatus.failed;
      default:
        return FaceStatus.notProcessed;
    }
  }
}

class PhotoMetadata {
  /// Unique photo identifier (matches Photo.id).
  final String photoId;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// File size in bytes.
  final int fileSizeBytes;

  /// MIME type (e.g., image/jpeg).
  final String? mimeType;

  /// Date the photo was created.
  final DateTime? dateCreated;

  /// Date the photo was last modified.
  final DateTime? dateModified;

  /// Camera make (e.g., Apple).
  final String? cameraMake;

  /// Camera model (e.g., iPhone 14 Pro).
  final String? cameraModel;

  /// ISO value.
  final int? iso;

  /// Shutter speed (e.g., 1/1000).
  final double? shutterSpeed;

  /// Aperture (f-stop, e.g., 1.8).
  final double? aperture;

  /// GPS latitude.
  final double? latitude;

  /// GPS longitude.
  final double? longitude;

  /// Image orientation in degrees (0, 90, 180, 270).
  final int orientation;

  /// Dominant color as ARGB integer.
  final int? dominantColor;

  /// Average color as ARGB integer.
  final int? averageColor;

  /// Brightness (0-1).
  final double? brightness;

  /// Contrast (0-1).
  final double? contrast;

  /// Blur score (0-1, higher is sharper).
  final double? blurScore;

  /// Overall quality score (0-1).
  final double? qualityScore;

  /// When this metadata was last indexed.
  final DateTime indexedAt;

  /// Album ID this photo belongs to.
  final String? albumId;

  /// Folder path this photo is located in.
  final String? folderPath;

  /// Media type (e.g., 'image', 'video').
  final String? mediaType;

  /// Duration in seconds (videos only, 0 for images).
  final int durationSeconds;

  /// OCR processing status.
  final OcrStatus ocrStatus;

  /// Version/hash of the OCR model used for this status (to detect when re-OCR is needed).
  final String? ocrModelVersion;

  /// Face processing status.
  final FaceStatus faceStatus;

  /// Version/hash of the face model used for this status (to detect when re-processing is needed).
  final String? faceModelVersion;

  const PhotoMetadata({
    required this.photoId,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    this.mimeType,
    this.dateCreated,
    this.dateModified,
    this.cameraMake,
    this.cameraModel,
    this.iso,
    this.shutterSpeed,
    this.aperture,
    this.latitude,
    this.longitude,
    required this.orientation,
    this.dominantColor,
    this.averageColor,
    this.brightness,
    this.contrast,
    this.blurScore,
    this.qualityScore,
    required this.indexedAt,
    this.albumId,
    this.folderPath,
    this.mediaType,
    this.durationSeconds = 0,
    this.ocrStatus = OcrStatus.notProcessed,
    this.ocrModelVersion,
    this.faceStatus = FaceStatus.notProcessed,
    this.faceModelVersion,
  });

  PhotoMetadata copyWith({
    String? photoId,
    int? width,
    int? height,
    int? fileSizeBytes,
    String? mimeType,
    DateTime? dateCreated,
    DateTime? dateModified,
    String? cameraMake,
    String? cameraModel,
    int? iso,
    double? shutterSpeed,
    double? aperture,
    double? latitude,
    double? longitude,
    int? orientation,
    int? dominantColor,
    int? averageColor,
    double? brightness,
    double? contrast,
    double? blurScore,
    double? qualityScore,
    DateTime? indexedAt,
    String? albumId,
    String? folderPath,
    String? mediaType,
    int? durationSeconds,
    OcrStatus? ocrStatus,
    String? ocrModelVersion,
    FaceStatus? faceStatus,
    String? faceModelVersion,
  }) {
    return PhotoMetadata(
      photoId: photoId ?? this.photoId,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      mimeType: mimeType ?? this.mimeType,
      dateCreated: dateCreated ?? this.dateCreated,
      dateModified: dateModified ?? this.dateModified,
      cameraMake: cameraMake ?? this.cameraMake,
      cameraModel: cameraModel ?? this.cameraModel,
      iso: iso ?? this.iso,
      shutterSpeed: shutterSpeed ?? this.shutterSpeed,
      aperture: aperture ?? this.aperture,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      orientation: orientation ?? this.orientation,
      dominantColor: dominantColor ?? this.dominantColor,
      averageColor: averageColor ?? this.averageColor,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      blurScore: blurScore ?? this.blurScore,
      qualityScore: qualityScore ?? this.qualityScore,
      indexedAt: indexedAt ?? this.indexedAt,
      albumId: albumId ?? this.albumId,
      folderPath: folderPath ?? this.folderPath,
      mediaType: mediaType ?? this.mediaType,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      ocrStatus: ocrStatus ?? this.ocrStatus,
      ocrModelVersion: ocrModelVersion ?? this.ocrModelVersion,
      faceStatus: faceStatus ?? this.faceStatus,
      faceModelVersion: faceModelVersion ?? this.faceModelVersion,
    );
  }

  /// Creates a PhotoMetadata from a database row map.
  static PhotoMetadata fromMap(Map<String, Object?> row) {
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
