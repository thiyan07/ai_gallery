import '../../../core/database/daos/analysis_dao.dart';
import '../../../core/database/daos/event_dao.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/photo_event.dart';

/// Clusters photos into events based on time, location, and visual similarity.
///
/// Uses a simple greedy clustering approach:
/// 1. Sort photos by capture time
/// 2. Start a new event if gap > threshold or location changed
/// 3. Assign event IDs to analysis_state
class EventClusteringService {
  EventClusteringService({
    required AnalysisDao analysisDao,
    required EventDao eventDao,
    AppLogger? logger,
  })  : _analysisDao = analysisDao,
        _eventDao = eventDao,
        _logger = logger;

  final AnalysisDao _analysisDao;
  final EventDao _eventDao;
  final AppLogger? _logger;

  /// Default gap threshold: 4 hours between photos = new event.
  static const defaultGapHours = 4;

  /// Default location change threshold: ~500m = location changed.
  static const defaultLocationThresholdDegrees = 0.005;

  /// Cluster all photos into events.
  Future<int> clusterAll({
    int gapHours = defaultGapHours,
    double locationThreshold = defaultLocationThresholdDegrees,
  }) async {
    _logger?.info('Starting event clustering');

    // Get all photos with timestamps from photo_metadata
    final rows = await _analysisDao.getPhotoTimeAndLocation();

    if (rows.isEmpty) {
      _logger?.info('No photos with timestamps found');
      return 0;
    }

    final photos = rows
        .map((r) => _PhotoInfo(
              id: r['id'] as String,
              dateTaken: DateTime.parse(r['date_taken'] as String),
              latitude: r['latitude'] as double?,
              longitude: r['longitude'] as double?,
            ))
        .toList();

    // Cluster into events
    final events = _clusterPhotos(
      photos,
      gapHours: gapHours,
      locationThreshold: locationThreshold,
    );

    // Store events and assign event IDs
    var newCount = 0;
    for (final event in events) {
      await _eventDao.upsert(event);
      await _analysisDao.setEventIds(event.photoIds, event.eventId);
      newCount++;
    }

    _logger?.info('Event clustering complete: $newCount events from ${photos.length} photos');
    return newCount;
  }

  /// Cluster photos based on time gaps and location changes.
  List<PhotoEvent> _clusterPhotos(
    List<_PhotoInfo> photos, {
    required int gapHours,
    required double locationThreshold,
  }) {
    if (photos.isEmpty) return [];

    final events = <PhotoEvent>[];
    var currentCluster = <_PhotoInfo>[photos.first];

    for (var i = 1; i < photos.length; i++) {
      final prev = photos[i - 1];
      final curr = photos[i];

      final timeGap = curr.dateTaken.difference(prev.dateTaken);
      final gapExceeded = timeGap.inHours >= gapHours;

      var locationChanged = false;
      if (prev.latitude != null &&
          prev.longitude != null &&
          curr.latitude != null &&
          curr.longitude != null) {
        final latDiff = (curr.latitude! - prev.latitude!).abs();
        final lngDiff = (curr.longitude! - prev.longitude!).abs();
        locationChanged =
            latDiff > locationThreshold || lngDiff > locationThreshold;
      }

      if (gapExceeded || locationChanged) {
        // Finish current cluster
        if (currentCluster.length >= 2) {
          events.add(_buildEvent(currentCluster));
        }
        currentCluster = [curr];
      } else {
        currentCluster.add(curr);
      }
    }

    // Don't forget the last cluster
    if (currentCluster.length >= 2) {
      events.add(_buildEvent(currentCluster));
    }

    return events;
  }

  /// Build a PhotoEvent from a cluster of photos.
  PhotoEvent _buildEvent(List<_PhotoInfo> cluster) {
    final photoIds = cluster.map((c) => c.id).toList();
    final startTime = cluster.first.dateTaken;
    final endTime = cluster.last.dateTaken;

    // Determine if location is available
    final withLocation = cluster.where((c) => c.latitude != null).toList();
    double? centerLat;
    double? centerLng;
    if (withLocation.isNotEmpty) {
      centerLat =
          withLocation.map((c) => c.latitude!).reduce((a, b) => a + b) /
              withLocation.length;
      centerLng =
          withLocation.map((c) => c.longitude!).reduce((a, b) => a + b) /
              withLocation.length;
    }

    // Generate title
    final title = _generateTitle(cluster, startTime, endTime);

    // Confidence based on photo count and time span
    final timeSpan = endTime.difference(startTime);
    final countScore = (cluster.length / 10).clamp(0.0, 1.0);
    final timeScore = (timeSpan.inHours / 8).clamp(0.0, 1.0);
    final confidence = (countScore * 0.4 + timeScore * 0.6).clamp(0.3, 1.0);

    return PhotoEvent(
      eventId: 'evt_${startTime.millisecondsSinceEpoch}',
      title: title,
      photoIds: photoIds,
      coverPhotoId: photoIds.first,
      startTime: startTime,
      endTime: endTime,
      latitude: centerLat,
      longitude: centerLng,
      confidence: confidence,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Generate a human-readable event title.
  String _generateTitle(
    List<_PhotoInfo> cluster,
    DateTime start,
    DateTime end,
  ) {
    final count = cluster.length;
    final isMultiDay = end.difference(start).inDays > 0;

    if (isMultiDay) {
      final days = end.difference(start).inDays + 1;
      return 'Event ($days days, $count photos)';
    }

    // Time-based title
    final hour = start.hour;
    if (hour >= 5 && hour < 12) {
      return 'Morning Event ($count photos)';
    } else if (hour >= 12 && hour < 17) {
      return 'Afternoon Event ($count photos)';
    } else if (hour >= 17 && hour < 21) {
      return 'Evening Event ($count photos)';
    } else {
      return 'Late Night Event ($count photos)';
    }
  }
}

class _PhotoInfo {
  final String id;
  final DateTime dateTaken;
  final double? latitude;
  final double? longitude;

  const _PhotoInfo({
    required this.id,
    required this.dateTaken,
    this.latitude,
    this.longitude,
  });
}
