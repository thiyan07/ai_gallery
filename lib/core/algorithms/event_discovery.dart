import 'temporal_clustering.dart';
import '../../domain/models/memory/photo_cluster.dart';

class EventDiscovery {
  static const minPhotos = 3;
  static const singleDayMaxHours = 14;

  static List<PhotoCluster> discover({
    required List<(String, DateTime)> photoTimestamps,
    int minimumPhotos = minPhotos,
  }) {
    if (photoTimestamps.length < minimumPhotos) return [];

    final sorted = List<(String, DateTime)>.from(photoTimestamps)
      ..sort((a, b) => a.$2.compareTo(b.$2));

    final clusters = TemporalClustering.clusterAdaptive(
      photoTimestamps: sorted,
    );

    return clusters.where((c) => c.photoCount >= minimumPhotos).toList();
  }

  static List<PhotoCluster> discoverEnhanced({
    required List<(String, DateTime)> photoTimestamps,
    int minimumPhotos = minPhotos,
    Map<String, (double, double)>? dateMetadata,
  }) {
    var clusters = discover(
      photoTimestamps: photoTimestamps,
      minimumPhotos: minimumPhotos,
    );

    clusters = TemporalClustering.mergeNearby(
      clusters: clusters,
      mergeThreshold: const Duration(hours: 2),
    );

    if (dateMetadata != null) {
      clusters = clusters.map((c) {
        final hasGps = c.photoIds.any((id) => dateMetadata.containsKey(id));
        return c.copyWith(hasGps: hasGps);
      }).toList();
    }

    return clusters;
  }

  static List<(DateTime, int)> findActivityHotspots({
    required List<(String, DateTime)> photoTimestamps,
    Duration windowSize = const Duration(hours: 1),
  }) {
    if (photoTimestamps.isEmpty) return [];

    final sorted = List<(String, DateTime)>.from(photoTimestamps)
      ..sort((a, b) => a.$2.compareTo(b.$2));

    final hotspots = <(DateTime, int)>[];

    for (var i = 0; i < sorted.length; i++) {
      final center = sorted[i].$2;
      final windowStart = center.subtract(windowSize ~/ 2);
      final windowEnd = center.add(windowSize ~/ 2);

      var count = 0;
      for (var j = 0; j < sorted.length; j++) {
        final ts = sorted[j].$2;
        if (ts.isAfter(windowStart) && ts.isBefore(windowEnd)) {
          count++;
        }
      }

      if (count >= 3) {
        hotspots.add((center, count));
      }
    }

    return hotspots;
  }

  static List<(DateTime start, DateTime end, Duration duration)> findGaps({
    required List<(String, DateTime)> photoTimestamps,
    Duration minGap = const Duration(hours: 6),
  }) {
    if (photoTimestamps.length < 2) return [];

    final sorted = List<(String, DateTime)>.from(photoTimestamps)
      ..sort((a, b) => a.$2.compareTo(b.$2));

    final gaps = <(DateTime, DateTime, Duration)>[];

    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].$2.difference(sorted[i - 1].$2);
      if (gap >= minGap) {
        gaps.add((sorted[i - 1].$2, sorted[i].$2, gap));
      }
    }

    return gaps;
  }
}
