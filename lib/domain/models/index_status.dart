/// Status of the overall indexing process.
enum IndexingPhase {
  scanning,
  extractingMetadata,
  generatingThumbnails,
  analyzingColors,
  detectingBlur,
  calculatingQuality,
  generatingEmbeddings,
  ocr,
  detectingObjects,
  detectingFaces,
  complete,
}

/// Current state of the indexing engine.
class IndexStatus {
  /// Whether indexing is currently running.
  final bool isRunning;

  /// Whether indexing is paused.
  final bool isPaused;

  /// Current phase of indexing.
  final IndexingPhase currentPhase;

  /// Total number of photos to index.
  final int totalPhotos;

  /// Number of photos processed so far.
  final int processedPhotos;

  /// Number of failed photos.
  final int failedPhotos;

  /// ID of the current photo being processed.
  final String? currentPhotoId;

  /// Estimated time remaining in seconds.
  final double? etaSeconds;

  /// When the indexing started.
  final DateTime? startedAt;

  const IndexStatus({
    required this.isRunning,
    required this.isPaused,
    required this.currentPhase,
    required this.totalPhotos,
    required this.processedPhotos,
    required this.failedPhotos,
    this.currentPhotoId,
    this.etaSeconds,
    this.startedAt,
  });

  double get progress => totalPhotos > 0 ? processedPhotos / totalPhotos : 0.0;

  IndexStatus copyWith({
    bool? isRunning,
    bool? isPaused,
    IndexingPhase? currentPhase,
    int? totalPhotos,
    int? processedPhotos,
    int? failedPhotos,
    String? currentPhotoId,
    double? etaSeconds,
    DateTime? startedAt,
  }) {
    return IndexStatus(
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      currentPhase: currentPhase ?? this.currentPhase,
      totalPhotos: totalPhotos ?? this.totalPhotos,
      processedPhotos: processedPhotos ?? this.processedPhotos,
      failedPhotos: failedPhotos ?? this.failedPhotos,
      currentPhotoId: currentPhotoId ?? this.currentPhotoId,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  static const initial = IndexStatus(
    isRunning: false,
    isPaused: false,
    currentPhase: IndexingPhase.scanning,
    totalPhotos: 0,
    processedPhotos: 0,
    failedPhotos: 0,
  );
}
