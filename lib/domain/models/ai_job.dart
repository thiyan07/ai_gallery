/// Status of a background AI processing job.
enum AIJobStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
}

/// Priority of a background AI processing job.
/// Higher values are processed first.
enum AIJobPriority {
  low(0),
  normal(1),
  high(2),
  critical(3);

  const AIJobPriority(this.value);
  final int value;
}

/// Type of AI processing job.
enum AIJobType {
  faceDetection,
  faceEmbedding,
  objectTagging,
  ocr,
  embedding,
  // Per-region (object crop) embeddings for precise search in complex scenes.
  regionEmbedding,
  caption,
  // Phase 25: Video-specific job types
  videoAnalysis,
  videoFrameExtraction,
  videoFrameOcr,
  videoFrameFaceDetection,
  videoFrameObjectDetection,
  videoEmbedding,
}

/// Domain model representing a queued or running AI background job.
class AIJob {
  /// Unique job identifier.
  final String id;

  /// Type of AI work to perform.
  final AIJobType type;

  /// Current job status.
  final AIJobStatus status;

  /// ID of the photo being processed.
  final String photoId;

  /// Progress from 0.0 to 1.0.
  final double progress;

  /// Error message if the job failed.
  final String? errorMessage;

  /// When the job was created.
  final DateTime createdAt;

  /// When the job started running, if applicable.
  final DateTime? startedAt;

  /// When the job finished, if applicable.
  final DateTime? completedAt;

  /// Number of times this job has been retried.
  final int retryCount;

  /// Priority of this job (higher = processed first).
  final AIJobPriority priority;

  const AIJob({
    required this.id,
    required this.type,
    required this.status,
    required this.photoId,
    this.progress = 0.0,
    this.errorMessage,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.retryCount = 0,
    this.priority = AIJobPriority.normal,
  });

  AIJob copyWith({
    String? id,
    AIJobType? type,
    AIJobStatus? status,
    String? photoId,
    double? progress,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    int? retryCount,
    AIJobPriority? priority,
  }) {
    return AIJob(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      photoId: photoId ?? this.photoId,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      retryCount: retryCount ?? this.retryCount,
      priority: priority ?? this.priority,
    );
  }
}
