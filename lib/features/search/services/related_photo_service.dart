import 'dart:math';

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';

/// Finds related photos using multi-signal analysis.
///
/// Two photos are "related" if they share multiple signals:
/// same person, same event, same location, same time, similar visual content.
class RelatedPhotoService {
  RelatedPhotoService({
    required AppDatabase database,
    AppLogger? logger,
  })  : _database = database,
        _logger = logger;

  final AppDatabase _database;
  final AppLogger? _logger;

  /// Find photos related to a given photo.
  ///
  /// Uses a weighted combination of:
  /// - Same event (weight: 0.3)
  /// - Same people (weight: 0.25)
  /// - Same location (weight: 0.2)
  /// - Similar time (weight: 0.15)
  /// - Visual similarity (weight: 0.1, from perceptual hash)
  Future<List<RelatedPhoto>> findRelated(
    String photoId, {
    int limit = 20,
    double minScore = 0.3,
  }) async {
    final photo = await _getPhotoInfo(photoId);
    if (photo == null) return [];

    final candidates = await _getPotentialCandidates(photoId);
    final scored = <RelatedPhoto>[];

    for (final candidate in candidates) {
      final score = _computeRelatednessScore(photo, candidate);
      if (score >= minScore) {
        scored.add(RelatedPhoto(
          photoId: candidate.id,
          score: score,
          reasons: _getReasons(photo, candidate),
        ));
      }
    }

    // Sort by score descending
    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.take(limit).toList();
  }

  /// Find the N most related photos, excluding the input photo.
  Future<List<String>> findRelatedIds(String photoId, {int limit = 10}) async {
    final related = await findRelated(photoId, limit: limit);
    return related.map((r) => r.photoId).toList();
  }

  /// Compute relatedness score between two photos.
  double _computeRelatednessScore(_PhotoInfo a, _PhotoInfo b) {
    var score = 0.0;
    var totalWeight = 0.0;

    // Same event (0.3)
    if (a.eventId != null && a.eventId == b.eventId) {
      score += 0.3;
    }
    totalWeight += 0.3;

    // Shared people (0.25)
    if (a.personIds.isNotEmpty && b.personIds.isNotEmpty) {
      final shared = a.personIds.toSet().intersection(b.personIds.toSet());
      final total = a.personIds.toSet().union(b.personIds.toSet());
      if (shared.isNotEmpty) {
        score += 0.25 * (shared.length / total.length);
      }
    }
    totalWeight += 0.25;

    // Same location (0.2)
    if (a.latitude != null &&
        b.latitude != null &&
        a.longitude != null &&
        b.longitude != null) {
      final distance = _haversineDistance(
        a.latitude!,
        a.longitude!,
        b.latitude!,
        b.longitude!,
      );
      // Within 1km = full score, linearly decreasing to 10km
      if (distance < 1.0) {
        score += 0.2;
      } else if (distance < 10.0) {
        score += 0.2 * (1.0 - (distance - 1.0) / 9.0);
      }
    }
    totalWeight += 0.2;

    // Time proximity (0.15)
    if (a.dateTaken != null && b.dateTaken != null) {
      final hoursDiff = a.dateTaken!.difference(b.dateTaken!).abs().inHours;
      if (hoursDiff < 1) {
        score += 0.15;
      } else if (hoursDiff < 24) {
        score += 0.15 * (1.0 - hoursDiff / 24.0);
      } else if (hoursDiff < 168) {
        // Within a week
        score += 0.05 * (1.0 - (hoursDiff - 24) / 144.0);
      }
    }
    totalWeight += 0.15;

    // Visual similarity from perceptual hash (0.1)
    if (a.perceptualHash != null && b.perceptualHash != null) {
      final distance = _hammingDistance(a.perceptualHash!, b.perceptualHash!);
      if (distance < 10) {
        score += 0.1 * (1.0 - distance / 64.0);
      }
    }
    totalWeight += 0.1;

    return totalWeight > 0 ? score / totalWeight : 0.0;
  }

  /// Get human-readable reasons for relatedness.
  List<String> _getReasons(_PhotoInfo a, _PhotoInfo b) {
    final reasons = <String>[];

    if (a.eventId != null && a.eventId == b.eventId) {
      reasons.add('Same event');
    }

    if (a.personIds.isNotEmpty && b.personIds.isNotEmpty) {
      final shared = a.personIds.toSet().intersection(b.personIds.toSet());
      if (shared.isNotEmpty) {
        reasons.add('Same ${shared.length} people');
      }
    }

    if (a.latitude != null &&
        b.latitude != null &&
        a.longitude != null &&
        b.longitude != null) {
      final distance = _haversineDistance(
        a.latitude!,
        a.longitude!,
        b.latitude!,
        b.longitude!,
      );
      if (distance < 1.0) {
        reasons.add('Same location');
      }
    }

    if (a.dateTaken != null && b.dateTaken != null) {
      final hours = a.dateTaken!.difference(b.dateTaken!).abs().inHours;
      if (hours < 1) {
        reasons.add('Taken within the same hour');
      } else if (hours < 24) {
        reasons.add('Taken on the same day');
      }
    }

    return reasons;
  }

  Future<_PhotoInfo?> _getPhotoInfo(String photoId) async {
    final rows = await _database.database.rawQuery(
      'SELECT p.id, p.date_taken, p.latitude, p.longitude, '
      'a.event_id, a.perceptual_hash, '
      'f.person_id '
      'FROM photos p '
      'LEFT JOIN analysis_state a ON p.id = a.photo_id '
      'LEFT JOIN faces f ON p.id = f.photo_id '
      'WHERE p.id = ?',
      [photoId],
    );

    if (rows.isEmpty) return null;

    final personIds = rows
        .where((r) => r['person_id'] != null)
        .map((r) => r['person_id'] as String)
        .toSet()
        .toList();

    return _PhotoInfo(
      id: rows.first['id'] as String,
      dateTaken: rows.first['date_taken'] != null
          ? DateTime.parse(rows.first['date_taken'] as String)
          : null,
      latitude: rows.first['latitude'] as double?,
      longitude: rows.first['longitude'] as double?,
      eventId: rows.first['event_id'] as String?,
      perceptualHash: rows.first['perceptual_hash'] as String?,
      personIds: personIds,
    );
  }

  Future<List<_PhotoInfo>> _getPotentialCandidates(String excludeId) async {
    // Get photos that share at least one signal with the target
    final rows = await _database.database.rawQuery(
      'SELECT DISTINCT p.id, p.date_taken, p.latitude, p.longitude, '
      'a.event_id, a.perceptual_hash '
      'FROM photos p '
      'LEFT JOIN analysis_state a ON p.id = a.photo_id '
      'LEFT JOIN faces f ON p.id = f.photo_id '
      'WHERE p.id != ? '
      'AND (a.event_id IS NOT NULL OR f.person_id IS NOT NULL '
      'OR p.latitude IS NOT NULL) '
      'LIMIT 500',
      [excludeId],
    );

    return rows.map((r) {
      return _PhotoInfo(
        id: r['id'] as String,
        dateTaken: r['date_taken'] != null
            ? DateTime.parse(r['date_taken'] as String)
            : null,
        latitude: r['latitude'] as double?,
        longitude: r['longitude'] as double?,
        eventId: r['event_id'] as String?,
        perceptualHash: r['perceptual_hash'] as String?,
        personIds: const [],
      );
    }).toList();
  }

  /// Haversine distance in km.
  double _haversineDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const r = 6371.0; // Earth radius in km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * pi / 180;

  int _hammingDistance(String h1, String h2) {
    if (h1.length != h2.length) return 64;
    final a = int.parse(h1, radix: 16);
    final b = int.parse(h2, radix: 16);
    var xor = a ^ b;
    var dist = 0;
    while (xor != 0) {
      dist++;
      xor &= xor - 1;
    }
    return dist;
  }
}

class _PhotoInfo {
  final String id;
  final DateTime? dateTaken;
  final double? latitude;
  final double? longitude;
  final String? eventId;
  final String? perceptualHash;
  final List<String> personIds;

  const _PhotoInfo({
    required this.id,
    this.dateTaken,
    this.latitude,
    this.longitude,
    this.eventId,
    this.perceptualHash,
    this.personIds = const [],
  });
}

/// A related photo with its relationship score and reasons.
class RelatedPhoto {
  final String photoId;
  final double score;
  final List<String> reasons;

  const RelatedPhoto({
    required this.photoId,
    required this.score,
    required this.reasons,
  });
}
