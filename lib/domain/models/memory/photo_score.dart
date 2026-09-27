/// Score assigned to a photo for ranking within a memory candidate.
class PhotoScore {
  final String photoId;
  final double qualityScore;
  final double blurScore;
  final double temporalScore;
  final double semanticScore;
  final double overallScore;
  final bool isCoverCandidate;

  const PhotoScore({
    required this.photoId,
    this.qualityScore = 0.0,
    this.blurScore = 0.0,
    this.temporalScore = 0.0,
    this.semanticScore = 0.0,
    this.overallScore = 0.0,
    this.isCoverCandidate = false,
  });

  PhotoScore copyWith({
    String? photoId,
    double? qualityScore,
    double? blurScore,
    double? temporalScore,
    double? semanticScore,
    double? overallScore,
    bool? isCoverCandidate,
  }) {
    return PhotoScore(
      photoId: photoId ?? this.photoId,
      qualityScore: qualityScore ?? this.qualityScore,
      blurScore: blurScore ?? this.blurScore,
      temporalScore: temporalScore ?? this.temporalScore,
      semanticScore: semanticScore ?? this.semanticScore,
      overallScore: overallScore ?? this.overallScore,
      isCoverCandidate: isCoverCandidate ?? this.isCoverCandidate,
    );
  }
}
