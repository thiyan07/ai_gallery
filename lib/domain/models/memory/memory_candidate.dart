import 'photo_cluster.dart';

/// A candidate group of photos that may become a memory after scoring.
class MemoryCandidate {
  final String candidateId;
  final PhotoCluster cluster;
  final double temporalScore;
  final double locationScore;
  final double peopleScore;
  final double semanticScore;
  final double qualityScore;
  final double overallScore;
  final String? suggestedTitle;
  final String? suggestedTheme;
  final bool isDuplicate;
  final List<String> overlappingCandidateIds;

  const MemoryCandidate({
    required this.candidateId,
    required this.cluster,
    this.temporalScore = 0.0,
    this.locationScore = 0.0,
    this.peopleScore = 0.0,
    this.semanticScore = 0.0,
    this.qualityScore = 0.0,
    this.overallScore = 0.0,
    this.suggestedTitle,
    this.suggestedTheme,
    this.isDuplicate = false,
    this.overlappingCandidateIds = const [],
  });

  List<String> get photoIds => cluster.photoIds;

  int get photoCount => cluster.photoCount;

  MemoryCandidate copyWith({
    String? candidateId,
    PhotoCluster? cluster,
    double? temporalScore,
    double? locationScore,
    double? peopleScore,
    double? semanticScore,
    double? qualityScore,
    double? overallScore,
    String? suggestedTitle,
    String? suggestedTheme,
    bool? isDuplicate,
    List<String>? overlappingCandidateIds,
  }) {
    return MemoryCandidate(
      candidateId: candidateId ?? this.candidateId,
      cluster: cluster ?? this.cluster,
      temporalScore: temporalScore ?? this.temporalScore,
      locationScore: locationScore ?? this.locationScore,
      peopleScore: peopleScore ?? this.peopleScore,
      semanticScore: semanticScore ?? this.semanticScore,
      qualityScore: qualityScore ?? this.qualityScore,
      overallScore: overallScore ?? this.overallScore,
      suggestedTitle: suggestedTitle ?? this.suggestedTitle,
      suggestedTheme: suggestedTheme ?? this.suggestedTheme,
      isDuplicate: isDuplicate ?? this.isDuplicate,
      overlappingCandidateIds: overlappingCandidateIds ?? this.overlappingCandidateIds,
    );
  }
}
