import 'dart:math' as math;

import '../../domain/models/memory/photo_cluster.dart';

/// Groups photos into temporal clusters based on time gaps.
///
/// Photos taken within [gapThreshold] of each other are grouped together.
/// This is the first step in event discovery — producing raw photo clusters
/// that will later be scored and refined by other algorithms.
class TemporalClustering {
  /// Default gap threshold: 4 hours.
  static const defaultGapThreshold = Duration(hours: 4);

  /// Maximum cluster size before splitting.
  static const maxClusterSize = 200;

  /// Minimum cluster size to be considered a potential memory.
  static const minClusterSize = 3;

  /// Groups a sorted list of (photoId, timestamp) pairs into clusters.
  ///
  /// [photoTimestamps] must be sorted by timestamp ascending.
  /// Returns a list of [PhotoCluster] objects.
  static List<PhotoCluster> cluster({
    required List<(String, DateTime)> photoTimestamps,
    Duration gapThreshold = defaultGapThreshold,
  }) {
    if (photoTimestamps.isEmpty) return [];

    final clusters = <PhotoCluster>[];
    var currentStart = 0;

    for (var i = 1; i < photoTimestamps.length; i++) {
      final gap = photoTimestamps[i].$2.difference(photoTimestamps[i - 1].$2);

      if (gap > gapThreshold) {
        final cluster = _buildCluster(
          photoTimestamps.sublist(currentStart, i),
          clusters.length,
        );
        if (cluster != null) clusters.add(cluster);
        currentStart = i;
      }
    }

    // Add the final cluster
    final lastCluster = _buildCluster(
      photoTimestamps.sublist(currentStart),
      clusters.length,
    );
    if (lastCluster != null) clusters.add(lastCluster);

    // Split oversized clusters
    return _splitOversized(clusters);
  }

  /// Groups photos using an adaptive gap threshold based on photo density.
  ///
  /// Analyzes the distribution of time gaps and picks a threshold that
  /// separates natural breaks in photo-taking activity.
  static List<PhotoCluster> clusterAdaptive({
    required List<(String, DateTime)> photoTimestamps,
  }) {
    if (photoTimestamps.length < 2) {
      if (photoTimestamps.isNotEmpty) {
        return [_buildCluster(photoTimestamps, 0)!].whereType<PhotoCluster>().toList();
      }
      return [];
    }

    // Compute gaps between consecutive photos
    final gaps = <Duration>[];
    for (var i = 1; i < photoTimestamps.length; i++) {
      gaps.add(photoTimestamps[i].$2.difference(photoTimestamps[i - 1].$2));
    }

    // Sort gaps and find the natural break point
    final sortedGaps = List<Duration>.from(gaps)..sort((a, b) => a.compareTo(b));

    // Use the largest gap that's still within a reasonable range (1-24h)
    // as the threshold. Fall back to default if no suitable gap found.
    Duration threshold = defaultGapThreshold;
    for (var i = sortedGaps.length - 1; i >= 0; i--) {
      final gap = sortedGaps[i];
      if (gap.inHours >= 1 && gap.inHours <= 24) {
        threshold = gap;
        break;
      }
    }

    return cluster(
      photoTimestamps: photoTimestamps,
      gapThreshold: threshold,
    );
  }

  /// Merges small adjacent clusters that are close in time.
  ///
  /// Useful when initial clustering is too aggressive and creates
  /// fragmented groups for what should be a single event.
  static List<PhotoCluster> mergeNearby({
    required List<PhotoCluster> clusters,
    Duration mergeThreshold = const Duration(hours: 2),
  }) {
    if (clusters.length <= 1) return clusters;

    final merged = <PhotoCluster>[];
    var current = clusters.first;

    for (var i = 1; i < clusters.length; i++) {
      final next = clusters[i];
      final gap = next.startDate.difference(current.endDate);

      if (gap <= mergeThreshold) {
        current = _mergeTwo(current, next, merged.length);
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);

    return merged;
  }

  static PhotoCluster? _buildCluster(
    List<(String, DateTime)> photoTimestamps,
    int index,
  ) {
    if (photoTimestamps.isEmpty) return null;

    final photoIds = photoTimestamps.map((p) => p.$1).toList();
    final startDate = photoTimestamps.first.$2;
    final endDate = photoTimestamps.last.$2;

    return PhotoCluster(
      clusterId: 'cluster_$index',
      photoIds: photoIds,
      startDate: startDate,
      endDate: endDate,
      span: endDate.difference(startDate),
    );
  }

  static List<PhotoCluster> _splitOversized(List<PhotoCluster> clusters) {
    final result = <PhotoCluster>[];
    var splitIndex = 0;

    for (final cluster in clusters) {
      if (cluster.photoCount <= maxClusterSize) {
        result.add(cluster.copyWith(clusterId: 'cluster_${splitIndex++}'));
      } else {
        // Split into chunks of maxClusterSize
        for (var i = 0; i < cluster.photoIds.length; i += maxClusterSize) {
          final end = math.min(i + maxClusterSize, cluster.photoIds.length);
          final chunkIds = cluster.photoIds.sublist(i, end);
          final chunkStart = i == 0
              ? cluster.startDate
              : cluster.startDate; // Approximate
          result.add(PhotoCluster(
            clusterId: 'cluster_${splitIndex++}',
            photoIds: chunkIds,
            startDate: chunkStart,
            endDate: cluster.endDate,
            span: cluster.span,
          ));
        }
      }
    }

    return result;
  }

  static PhotoCluster _mergeTwo(PhotoCluster a, PhotoCluster b, int index) {
    return PhotoCluster(
      clusterId: 'cluster_$index',
      photoIds: [...a.photoIds, ...b.photoIds],
      startDate: a.startDate.isBefore(b.startDate) ? a.startDate : b.startDate,
      endDate: a.endDate.isAfter(b.endDate) ? a.endDate : b.endDate,
      span: (a.endDate.isAfter(b.endDate) ? a.endDate : b.endDate)
          .difference(a.startDate.isBefore(b.startDate) ? a.startDate : b.startDate),
    );
  }
}
