/// Represents a detected trip or outing from photo metadata.
class TripEvent {
  final String tripId;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> photoIds;
  final double? startLatitude;
  final double? startLongitude;
  final double? endLatitude;
  final double? endLongitude;
  final List<String> locationLabels;
  final int photoCount;

  const TripEvent({
    required this.tripId,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.photoIds,
    this.startLatitude,
    this.startLongitude,
    this.endLatitude,
    this.endLongitude,
    this.locationLabels = const [],
    required this.photoCount,
  });

  Duration get duration => endDate.difference(startDate);

  bool get isMultiDay => duration.inDays > 0;

  TripEvent copyWith({
    String? tripId,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? photoIds,
    double? startLatitude,
    double? startLongitude,
    double? endLatitude,
    double? endLongitude,
    List<String>? locationLabels,
    int? photoCount,
  }) {
    return TripEvent(
      tripId: tripId ?? this.tripId,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      photoIds: photoIds ?? this.photoIds,
      startLatitude: startLatitude ?? this.startLatitude,
      startLongitude: startLongitude ?? this.startLongitude,
      endLatitude: endLatitude ?? this.endLatitude,
      endLongitude: endLongitude ?? this.endLongitude,
      locationLabels: locationLabels ?? this.locationLabels,
      photoCount: photoCount ?? this.photoCount,
    );
  }
}
