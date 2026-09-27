/// Detailed view of a memory with enriched photo data.
class MemoryDetail {
  final MemorySummary memory;
  final List<MemoryPhoto> photos;
  final List<String> detectedThemes;
  final String? tripLocation;
  final bool hasPeople;
  final int totalPhotos;

  const MemoryDetail({
    required this.memory,
    required this.photos,
    this.detectedThemes = const [],
    this.tripLocation,
    this.hasPeople = false,
    required this.totalPhotos,
  });

  List<MemoryPhoto> get sortedPhotos =>
      List.of(photos)..sort((a, b) => a.order.compareTo(b.order));

  MemoryPhoto? get coverPhoto =>
      photos.firstWhereOrNull((p) => p.isCover);

  List<String> get personNames =>
      photos.expand((p) => p.personNames).toSet().toList();
}

class MemorySummary {
  final String memoryId;
  final String title;
  final String? subtitle;
  final String coverPhotoId;
  final DateTime startDate;
  final DateTime endDate;
  final double score;
  final String themeLabel;
  final int photoCount;
  final String? locationLabel;

  const MemorySummary({
    required this.memoryId,
    required this.title,
    this.subtitle,
    required this.coverPhotoId,
    required this.startDate,
    required this.endDate,
    required this.score,
    required this.themeLabel,
    required this.photoCount,
    this.locationLabel,
  });
}

class MemoryPhoto {
  final String photoId;
  final DateTime? dateCreated;
  final double? qualityScore;
  final double? blurScore;
  final List<String> objectLabels;
  final List<String> personNames;
  final bool isCover;
  final int order;
  final double? latitude;
  final double? longitude;

  const MemoryPhoto({
    required this.photoId,
    this.dateCreated,
    this.qualityScore,
    this.blurScore,
    this.objectLabels = const [],
    this.personNames = const [],
    this.isCover = false,
    this.order = 0,
    this.latitude,
    this.longitude,
  });
}

extension _ListExtension<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
