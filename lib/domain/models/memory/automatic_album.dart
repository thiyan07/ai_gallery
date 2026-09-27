/// Types of automatically generated albums.
enum AutomaticAlbumType {
  bestOfYear,
  monthlyHighlights,
  trip,
  event,
  people,
  seasonal,
  recurring,
  place,
}

/// Represents a virtual automatic album generated from photo analysis.
class AutomaticAlbum {
  final String albumId;
  final String title;
  final AutomaticAlbumType type;
  final List<String> photoIds;
  final String coverPhotoId;
  final DateTime startDate;
  final DateTime endDate;
  final double score;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isHidden;
  final String? locationLabel;
  final int? year;
  final int? month;

  const AutomaticAlbum({
    required this.albumId,
    required this.title,
    required this.type,
    required this.photoIds,
    required this.coverPhotoId,
    required this.startDate,
    required this.endDate,
    required this.score,
    required this.createdAt,
    required this.updatedAt,
    this.isHidden = false,
    this.locationLabel,
    this.year,
    this.month,
  });

  int get photoCount => photoIds.length;

  String get typeLabel {
    switch (type) {
      case AutomaticAlbumType.bestOfYear:
        return 'Best of Year';
      case AutomaticAlbumType.monthlyHighlights:
        return 'Monthly Highlights';
      case AutomaticAlbumType.trip:
        return 'Trip';
      case AutomaticAlbumType.event:
        return 'Event';
      case AutomaticAlbumType.people:
        return 'People';
      case AutomaticAlbumType.seasonal:
        return 'Seasonal';
      case AutomaticAlbumType.recurring:
        return 'Recurring';
      case AutomaticAlbumType.place:
        return 'Place';
    }
  }

  AutomaticAlbum copyWith({
    String? albumId,
    String? title,
    AutomaticAlbumType? type,
    List<String>? photoIds,
    String? coverPhotoId,
    DateTime? startDate,
    DateTime? endDate,
    double? score,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isHidden,
    String? locationLabel,
    int? year,
    int? month,
  }) {
    return AutomaticAlbum(
      albumId: albumId ?? this.albumId,
      title: title ?? this.title,
      type: type ?? this.type,
      photoIds: photoIds ?? this.photoIds,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      score: score ?? this.score,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isHidden: isHidden ?? this.isHidden,
      locationLabel: locationLabel ?? this.locationLabel,
      year: year ?? this.year,
      month: month ?? this.month,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'album_id': albumId,
      'title': title,
      'type': type.index,
      'photo_ids': photoIds.join(','),
      'cover_photo_id': coverPhotoId,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'score': score,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_hidden': isHidden ? 1 : 0,
      'location_label': locationLabel,
      'year': year,
      'month': month,
    };
  }

  factory AutomaticAlbum.fromMap(Map<String, Object?> row) {
    return AutomaticAlbum(
      albumId: row['album_id'] as String,
      title: row['title'] as String,
      type: AutomaticAlbumType.values[row['type'] as int],
      photoIds: (row['photo_ids'] as String).split(',').where((s) => s.isNotEmpty).toList(),
      coverPhotoId: row['cover_photo_id'] as String,
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: DateTime.parse(row['end_date'] as String),
      score: row['score'] as double,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      isHidden: (row['is_hidden'] as int) == 1,
      locationLabel: row['location_label'] as String?,
      year: row['year'] as int?,
      month: row['month'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutomaticAlbum && runtimeType == other.runtimeType && albumId == other.albumId;

  @override
  int get hashCode => albumId.hashCode;
}
