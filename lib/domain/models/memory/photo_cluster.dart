/// Represents a group of photos that are temporally close.
class PhotoCluster {
  final String clusterId;
  final List<String> photoIds;
  final DateTime startDate;
  final DateTime endDate;
  final Duration span;
  final double avgQualityScore;
  final bool hasGps;
  final bool hasPeople;

  const PhotoCluster({
    required this.clusterId,
    required this.photoIds,
    required this.startDate,
    required this.endDate,
    required this.span,
    this.avgQualityScore = 0.0,
    this.hasGps = false,
    this.hasPeople = false,
  });

  int get photoCount => photoIds.length;

  bool get isMultiDay => span.inDays > 0;

  PhotoCluster copyWith({
    String? clusterId,
    List<String>? photoIds,
    DateTime? startDate,
    DateTime? endDate,
    Duration? span,
    double? avgQualityScore,
    bool? hasGps,
    bool? hasPeople,
  }) {
    return PhotoCluster(
      clusterId: clusterId ?? this.clusterId,
      photoIds: photoIds ?? this.photoIds,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      span: span ?? this.span,
      avgQualityScore: avgQualityScore ?? this.avgQualityScore,
      hasGps: hasGps ?? this.hasGps,
      hasPeople: hasPeople ?? this.hasPeople,
    );
  }
}
