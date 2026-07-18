/// Domain model representing a photo or video asset from the device library.
class Photo {
  /// Unique asset identifier from the device media library.
  final String id;

  /// Album this photo belongs to, if known.
  final String? albumId;

  /// Pixel width of the original asset.
  final int width;

  /// Pixel height of the original asset.
  final int height;

  /// When the photo was taken or added to the library.
  final DateTime? createdAt;

  /// Whether this asset is a video.
  final bool isVideo;

  /// Duration in seconds (videos only).
  final int durationSeconds;

  /// Whether the user has marked this photo as a favorite.
  final bool isFavorite;

  const Photo({
    required this.id,
    this.albumId,
    required this.width,
    required this.height,
    this.createdAt,
    this.isVideo = false,
    this.durationSeconds = 0,
    this.isFavorite = false,
  });

  Photo copyWith({
    String? id,
    String? albumId,
    int? width,
    int? height,
    DateTime? createdAt,
    bool? isVideo,
    int? durationSeconds,
    bool? isFavorite,
  }) {
    return Photo(
      id: id ?? this.id,
      albumId: albumId ?? this.albumId,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
      isVideo: isVideo ?? this.isVideo,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Photo && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
