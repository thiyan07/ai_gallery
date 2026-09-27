/// Domain model representing a photo asset from the device library.
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

  /// Whether the user has marked this photo as a favorite.
  final bool isFavorite;

  const Photo({
    required this.id,
    this.albumId,
    required this.width,
    required this.height,
    this.createdAt,
    this.isFavorite = false,
  });

  Photo copyWith({
    String? id,
    String? albumId,
    int? width,
    int? height,
    DateTime? createdAt,
    bool? isFavorite,
  }) {
    return Photo(
      id: id ?? this.id,
      albumId: albumId ?? this.albumId,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
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
