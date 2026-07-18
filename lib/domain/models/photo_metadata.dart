/// Domain model representing metadata extracted from a photo.
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
    );
  }
}
