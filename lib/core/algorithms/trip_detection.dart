import 'dart:math' as math;

import '../../domain/models/memory/trip_event.dart';
import '../../domain/models/memory/photo_cluster.dart';

/// Detects trips and outings from photo metadata.
///
/// A trip is defined as a group of photos taken in a different location
/// from the user's "home" area, typically spanning multiple days.
class TripDetection {
  /// Minimum distance from home to be considered a trip (in degrees, ~50km).
  static const minDistanceFromHome = 0.5;

  /// Minimum photos for a trip.
  static const minPhotosForTrip = 5;

  /// Maximum gap between photos to still be part of the same trip.
  static const maxGapForTrip = Duration(days: 2);

  /// Detects trips from a list of photo clusters with GPS data.
  ///
  /// [clusters] — temporally clustered photos
  /// [gpsData] — map of photoId to (latitude, longitude)
  /// [homeLocation] — user's home location (latitude, longitude), optional
  /// Returns a list of [TripEvent] objects.
  static List<TripEvent> detectTrips({
    required List<PhotoCluster> clusters,
    required Map<String, (double, double)> gpsData,
    (double, double)? homeLocation,
  }) {
    final trips = <TripEvent>[];

    for (final cluster in clusters) {
      if (cluster.photoCount < minPhotosForTrip) continue;

      // Get GPS data for this cluster
      final clusterGps = <String, (double, double)>{};
      for (final photoId in cluster.photoIds) {
        if (gpsData.containsKey(photoId)) {
          clusterGps[photoId] = gpsData[photoId]!;
        }
      }

      if (clusterGps.isEmpty) continue;

      // Check if photos are far from home
      if (homeLocation != null) {
        final avgLat = clusterGps.values.map((l) => l.$1).reduce((a, b) => a + b) / clusterGps.length;
        final avgLng = clusterGps.values.map((l) => l.$2).reduce((a, b) => a + b) / clusterGps.length;
        final distance = _haversineDistance(homeLocation.$1, homeLocation.$2, avgLat, avgLng);

        if (distance < minDistanceFromHome) continue;
      }

      // Extract location labels (simplified: use lat/lng ranges)
      final locations = _extractLocationLabels(clusterGps);

      // Create trip event
      final trip = TripEvent(
        tripId: 'trip_${trips.length}',
        title: _generateTripTitle(locations, cluster.startDate),
        startDate: cluster.startDate,
        endDate: cluster.endDate,
        photoIds: cluster.photoIds,
        startLatitude: clusterGps.values.first.$1,
        startLongitude: clusterGps.values.first.$2,
        endLatitude: clusterGps.values.last.$1,
        endLongitude: clusterGps.values.last.$2,
        locationLabels: locations,
        photoCount: cluster.photoCount,
      );

      trips.add(trip);
    }

    // Merge overlapping trips
    return _mergeOverlappingTrips(trips);
  }

  /// Detects trips using an even simpler heuristic: just look at GPS spread.
  ///
  /// Useful when home location is unknown.
  static List<TripEvent> detectTripsSimple({
    required List<PhotoCluster> clusters,
    required Map<String, (double, double)> gpsData,
  }) {
    final trips = <TripEvent>[];

    for (final cluster in clusters) {
      if (cluster.photoCount < minPhotosForTrip) continue;

      final clusterGps = <String, (double, double)>{};
      for (final photoId in cluster.photoIds) {
        if (gpsData.containsKey(photoId)) {
          clusterGps[photoId] = gpsData[photoId]!;
        }
      }

      if (clusterGps.length < minPhotosForTrip) continue;

      // Check GPS spread — large spread = trip
      final spread = _calculateGpsSpread(clusterGps.values.toList());
      if (spread < minDistanceFromHome * 0.5) continue;

      final locations = _extractLocationLabels(clusterGps);

      trips.add(TripEvent(
        tripId: 'trip_${trips.length}',
        title: _generateTripTitle(locations, cluster.startDate),
        startDate: cluster.startDate,
        endDate: cluster.endDate,
        photoIds: cluster.photoIds,
        locationLabels: locations,
        photoCount: cluster.photoCount,
      ));
    }

    return _mergeOverlappingTrips(trips);
  }

  static double _haversineDistance(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0; // Earth radius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c / 111.0; // Convert km to degrees (approx)
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;

  static double _calculateGpsSpread(List<(double, double)> locations) {
    if (locations.length < 2) return 0.0;
    final lats = locations.map((l) => l.$1).toList();
    final lngs = locations.map((l) => l.$2).toList();
    final latRange = lats.reduce(math.max) - lats.reduce(math.min);
    final lngRange = lngs.reduce(math.max) - lngs.reduce(math.min);
    return math.max(latRange, lngRange);
  }

  static List<String> _extractLocationLabels(Map<String, (double, double)> gpsData) {
    final labels = <String>{};
    for (final entry in gpsData.entries) {
      final coords = entry.value;
      labels.add('${coords.$1.toStringAsFixed(1)}°, ${coords.$2.toStringAsFixed(1)}°');
    }
    return labels.toList();
  }

  static String _generateTripTitle(List<String> locations, DateTime startDate) {
    final month = _monthNames[startDate.month - 1];
    if (locations.isNotEmpty) {
      return 'Trip to ${locations.first} ($month)';
    }
    return 'Trip ($month)';
  }

  static List<TripEvent> _mergeOverlappingTrips(List<TripEvent> trips) {
    if (trips.length <= 1) return trips;

    final sorted = List<TripEvent>.from(trips)
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final merged = <TripEvent>[];
    var current = sorted.first;

    for (var i = 1; i < sorted.length; i++) {
      final next = sorted[i];
      final gap = next.startDate.difference(current.endDate);

      if (gap <= maxGapForTrip) {
        // Merge
        final allPhotos = [...current.photoIds, ...next.photoIds];
        current = TripEvent(
          tripId: current.tripId,
          title: current.title,
          startDate: current.startDate.isBefore(next.startDate) ? current.startDate : next.startDate,
          endDate: current.endDate.isAfter(next.endDate) ? current.endDate : next.endDate,
          photoIds: allPhotos,
          locationLabels: [...current.locationLabels, ...next.locationLabels].toSet().toList(),
          photoCount: allPhotos.length,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);

    return merged;
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
