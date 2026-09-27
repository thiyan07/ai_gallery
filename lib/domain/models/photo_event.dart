/// Represents a clustered event — a group of photos taken at roughly
/// the same time and place, potentially featuring the same people.
class PhotoEvent {
  final String eventId;
  final String title;
  final String? subtitle;
  final List<String> photoIds;
  final String? coverPhotoId;
  final DateTime startTime;
  final DateTime endTime;
  final String? locationLabel;
  final double? latitude;
  final double? longitude;
  final List<String> personIds;
  final double confidence;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PhotoEvent({
    required this.eventId,
    required this.title,
    this.subtitle,
    required this.photoIds,
    this.coverPhotoId,
    required this.startTime,
    required this.endTime,
    this.locationLabel,
    this.latitude,
    this.longitude,
    this.personIds = const [],
    required this.confidence,
    required this.createdAt,
    required this.updatedAt,
  });

  int get photoCount => photoIds.length;

  bool get isMultiDay => endTime.difference(startTime).inDays > 0;

  Duration get duration => endTime.difference(startTime);

  PhotoEvent copyWith({
    String? eventId,
    String? title,
    String? subtitle,
    List<String>? photoIds,
    String? coverPhotoId,
    DateTime? startTime,
    DateTime? endTime,
    String? locationLabel,
    double? latitude,
    double? longitude,
    List<String>? personIds,
    double? confidence,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PhotoEvent(
      eventId: eventId ?? this.eventId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      photoIds: photoIds ?? this.photoIds,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      locationLabel: locationLabel ?? this.locationLabel,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      personIds: personIds ?? this.personIds,
      confidence: confidence ?? this.confidence,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'event_id': eventId,
        'title': title,
        'subtitle': subtitle,
        'photo_ids': photoIds.join(','),
        'cover_photo_id': coverPhotoId,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'location_label': locationLabel,
        'latitude': latitude,
        'longitude': longitude,
        'person_ids': personIds.join(','),
        'confidence': confidence,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory PhotoEvent.fromMap(Map<String, Object?> row) => PhotoEvent(
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoEvent &&
          runtimeType == other.runtimeType &&
          eventId == other.eventId;

  @override
  int get hashCode => eventId.hashCode;
}
