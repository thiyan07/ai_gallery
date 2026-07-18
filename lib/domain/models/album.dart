/// Domain model representing a photo album on the device.
class Album {
  /// Unique album identifier from the device media library.
  final String id;

  /// Display name of the album.
  final String name;

  /// Number of assets in the album.
  final int assetCount;

  /// Whether this album represents all photos on the device.
  final bool isAllPhotos;

  const Album({
    required this.id,
    required this.name,
    required this.assetCount,
    this.isAllPhotos = false,
  });

  Album copyWith({
    String? id,
    String? name,
    int? assetCount,
    bool? isAllPhotos,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      assetCount: assetCount ?? this.assetCount,
      isAllPhotos: isAllPhotos ?? this.isAllPhotos,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
