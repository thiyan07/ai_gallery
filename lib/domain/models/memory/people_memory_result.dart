/// A memory result grouped by people present in photos.
class PeopleMemoryResult {
  final String personId;
  final String? personName;
  final List<String> photoIds;
  final DateTime startDate;
  final DateTime endDate;
  final double score;
  final String? coverPhotoId;
  final String? eventLabel;

  const PeopleMemoryResult({
    required this.personId,
    this.personName,
    required this.photoIds,
    required this.startDate,
    required this.endDate,
    this.score = 0.0,
    this.coverPhotoId,
    this.eventLabel,
  });

  int get photoCount => photoIds.length;

  PeopleMemoryResult copyWith({
    String? personId,
    String? personName,
    List<String>? photoIds,
    DateTime? startDate,
    DateTime? endDate,
    double? score,
    String? coverPhotoId,
    String? eventLabel,
  }) {
    return PeopleMemoryResult(
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      photoIds: photoIds ?? this.photoIds,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      score: score ?? this.score,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      eventLabel: eventLabel ?? this.eventLabel,
    );
  }
}
