/// Tracks the analysis state for a video beyond what photo_metadata stores.
enum VideoAnalysisStatus {
  notAnalyzed,
  queued,
  processing,
  partiallyAnalyzed,
  complete,
  failed,
  requiresReprocessing,
}

extension VideoAnalysisStatusExtension on int {
  VideoAnalysisStatus toVideoAnalysisStatus() {
    switch (this) {
      case 0:
        return VideoAnalysisStatus.notAnalyzed;
      case 1:
        return VideoAnalysisStatus.queued;
      case 2:
        return VideoAnalysisStatus.processing;
      case 3:
        return VideoAnalysisStatus.partiallyAnalyzed;
      case 4:
        return VideoAnalysisStatus.complete;
      case 5:
        return VideoAnalysisStatus.failed;
      case 6:
        return VideoAnalysisStatus.requiresReprocessing;
      default:
        return VideoAnalysisStatus.notAnalyzed;
    }
  }
}

class VideoAnalysis {
  final String videoId;
  final VideoAnalysisStatus analysisStatus;
  final int totalFramesSampled;
  final String? representativeFramesJson;
  final int sceneCount;
  final bool hasAudio;
  final int transcriptionStatus;
  final int embeddingStatus;
  final double? qualityScore;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VideoAnalysis({
    required this.videoId,
    this.analysisStatus = VideoAnalysisStatus.notAnalyzed,
    this.totalFramesSampled = 0,
    this.representativeFramesJson,
    this.sceneCount = 0,
    this.hasAudio = false,
    this.transcriptionStatus = 0,
    this.embeddingStatus = 0,
    this.qualityScore,
    required this.createdAt,
    required this.updatedAt,
  });

  VideoAnalysis copyWith({
    VideoAnalysisStatus? analysisStatus,
    int? totalFramesSampled,
    String? representativeFramesJson,
    int? sceneCount,
    bool? hasAudio,
    int? transcriptionStatus,
    int? embeddingStatus,
    double? qualityScore,
  }) {
    return VideoAnalysis(
      videoId: videoId,
      analysisStatus: analysisStatus ?? this.analysisStatus,
      totalFramesSampled: totalFramesSampled ?? this.totalFramesSampled,
      representativeFramesJson: representativeFramesJson ?? this.representativeFramesJson,
      sceneCount: sceneCount ?? this.sceneCount,
      hasAudio: hasAudio ?? this.hasAudio,
      transcriptionStatus: transcriptionStatus ?? this.transcriptionStatus,
      embeddingStatus: embeddingStatus ?? this.embeddingStatus,
      qualityScore: qualityScore ?? this.qualityScore,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
        'video_id': videoId,
        'analysis_status': analysisStatus.index,
        'total_frames_sampled': totalFramesSampled,
        'representative_frames_json': representativeFramesJson,
        'scene_count': sceneCount,
        'has_audio': hasAudio ? 1 : 0,
        'transcription_status': transcriptionStatus,
        'embedding_status': embeddingStatus,
        'quality_score': qualityScore,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory VideoAnalysis.fromMap(Map<String, Object?> row) {
    return VideoAnalysis(
      videoId: row['video_id'] as String,
      analysisStatus: (row['analysis_status'] as int).toVideoAnalysisStatus(),
      totalFramesSampled: row['total_frames_sampled'] as int? ?? 0,
      representativeFramesJson: row['representative_frames_json'] as String?,
      sceneCount: row['scene_count'] as int? ?? 0,
      hasAudio: (row['has_audio'] as int? ?? 0) == 1,
      transcriptionStatus: row['transcription_status'] as int? ?? 0,
      embeddingStatus: row['embedding_status'] as int? ?? 0,
      qualityScore: row['quality_score'] as double?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
