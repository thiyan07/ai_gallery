import 'package:sqflite/sqflite.dart';

import '../../../domain/models/photo_event.dart';

/// Data access object for the photo_events table.
class EventDao {
  const EventDao(this._db);

  final Database _db;

  /// Upsert a photo event.
  Future<void> upsert(PhotoEvent event) async {
    await _db.insert(
      'photo_events',
      _toRow(event),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all events, ordered by start time descending.
  Future<List<PhotoEvent>> getAll() async {
    final rows = await _db.query('photo_events', orderBy: 'start_time DESC');
    return rows.map(_fromRow).toList();
  }

  /// Get an event by ID.
  Future<PhotoEvent?> getById(String eventId) async {
    final rows = await _db.query(
      'photo_events',
      where: 'event_id = ?',
      whereArgs: [eventId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Get events containing a specific photo.
  Future<List<PhotoEvent>> getByPhotoId(String photoId) async {
    // Match the photo ID as a whole comma-delimited token to avoid substring
    // false positives (e.g. matching "1" inside "10" or "100"). The photo_ids
    // column stores a comma-separated list, so the ID may appear as the only
    // entry, the first, the last, or in the middle.
    final rows = await _db.query(
      'photo_events',
      where: 'photo_ids = ? OR photo_ids LIKE ? OR photo_ids LIKE ? OR photo_ids LIKE ?',
      whereArgs: [
        photoId,
        '$photoId,%',
        '%,$photoId',
        '%,$photoId,%',
      ],
      orderBy: 'start_time DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Get events within a date range.
  Future<List<PhotoEvent>> getByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _db.query(
      'photo_events',
      where: 'start_time >= ? AND start_time <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'start_time DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Get events near a location (within approximate bounding box).
  Future<List<PhotoEvent>> getByLocation(
    double lat,
    double lng, {
    double radiusDegrees = 0.1,
  }) async {
    final rows = await _db.query(
      'photo_events',
      where: 'latitude IS NOT NULL AND longitude IS NOT NULL '
          'AND latitude BETWEEN ? AND ? '
          'AND longitude BETWEEN ? AND ?',
      whereArgs: [
        lat - radiusDegrees,
        lat + radiusDegrees,
        lng - radiusDegrees,
        lng + radiusDegrees,
      ],
      orderBy: 'start_time DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Delete an event by ID.
  Future<void> deleteById(String eventId) async {
    await _db.delete('photo_events', where: 'event_id = ?', whereArgs: [eventId]);
  }

  /// Count total events.
  Future<int> count() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as c FROM photo_events');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Watch event count.
  Stream<int> watchCount() {
    return _db
        .rawQuery('SELECT COUNT(*) as c FROM photo_events')
        .asStream()
        .map((rows) => Sqflite.firstIntValue(rows) ?? 0);
  }

  Map<String, Object?> _toRow(PhotoEvent e) => {
        'event_id': e.eventId,
        'title': e.title,
        'subtitle': e.subtitle,
        'photo_ids': e.photoIds.join(','),
        'cover_photo_id': e.coverPhotoId,
        'start_time': e.startTime.toIso8601String(),
        'end_time': e.endTime.toIso8601String(),
        'location_label': e.locationLabel,
        'latitude': e.latitude,
        'longitude': e.longitude,
        'person_ids': e.personIds.join(','),
        'confidence': e.confidence,
        'created_at': e.createdAt.toIso8601String(),
        'updated_at': e.updatedAt.toIso8601String(),
      };

  PhotoEvent _fromRow(Map<String, Object?> row) => PhotoEvent(
        eventId: row['event_id'] as String,
        title: row['title'] as String,
        subtitle: row['subtitle'] as String?,
        photoIds: (row['photo_ids'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
        coverPhotoId: row['cover_photo_id'] as String?,
        startTime: DateTime.parse(row['start_time'] as String),
        endTime: DateTime.parse(row['end_time'] as String),
        locationLabel: row['location_label'] as String?,
        latitude: row['latitude'] as double?,
        longitude: row['longitude'] as double?,
        personIds: (row['person_ids'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
        confidence: row['confidence'] as double,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}
