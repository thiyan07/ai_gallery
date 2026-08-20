/// Domain model representing a person or group of people.
enum PersonStatus {
  active,
  merged,
  deleted,
}

extension PersonStatusExtension on PersonStatus {
  String toValue() {
    switch (this) {
      case PersonStatus.active:
        return 'active';
      case PersonStatus.merged:
        return 'merged';
      case PersonStatus.deleted:
        return 'deleted';
    }
  }

  static PersonStatus fromValue(String value) {
    switch (value) {
      case 'active':
        return PersonStatus.active;
      case 'merged':
        return PersonStatus.merged;
      case 'deleted':
        return PersonStatus.deleted;
      default:
        return PersonStatus.active;
    }
  }
}

/// Domain model representing a person or group of people.
class Person {
  /// Unique identifier for this person.
  final String personId;

  /// Display name of the person (can be null for unknown people).
  final String? displayName;

  /// Timestamp when this person was created.
  final DateTime createdAt;

  /// Timestamp when this person was last updated.
  final DateTime updatedAt;

  /// Photo ID of the cover photo for this person (can be null).
  final String? coverPhotoId;

  /// Current status of the person.
  final PersonStatus status;

  const Person({
    required this.personId,
    this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.coverPhotoId,
    this.status = PersonStatus.active,
  });

  Person copyWith({
    String? personId,
    String? displayName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? coverPhotoId,
    PersonStatus? status,
  }) {
    return Person(
      personId: personId ?? this.personId,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      status: status ?? this.status,
    );
  }

  /// Creates a Person from a database row map.
  factory Person.fromMap(Map<String, Object?> row) {
    return Person(
      personId: row['person_id'] as String,
      displayName: row['display_name'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      coverPhotoId: row['cover_photo_id'] as String?,
      status: PersonStatusExtension.fromValue(row['status'] as String),
    );
  }

  /// Converts this Person to a database row map.
  Map<String, Object?> toMap() {
    return {
      'person_id': personId,
      'display_name': displayName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'cover_photo_id': coverPhotoId,
      'status': status.toValue(),
    };
  }
}