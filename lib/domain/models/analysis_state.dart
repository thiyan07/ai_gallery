/// Tracks the analysis state of a single photo across all AI pipelines.
///
/// This is the core of incremental analysis — each photo tracks what
/// has been computed, what version of the model was used, and what
/// needs recomputation.
class AnalysisState {
  final String photoId;

  /// Content hash (SHA-256 of file bytes) for exact duplicate detection.
  final String? contentHash;

  /// Perceptual hash (pHash) for near-duplicate detection.
  final String? perceptualHash;

  /// Blur classification.
  final BlurClassification blurClassification;

  /// Exposure classification.
  final ExposureClassification exposureClassification;

  /// Quality score (0.0–1.0).
  final double? qualityScore;

  /// Whether this photo is likely a screenshot.
  final bool? isScreenshot;

  /// Whether this photo is likely a document.
  final bool? isDocument;

  /// Detected scene labels (comma-separated).
  final String? sceneLabels;

  /// Detected activity labels (comma-separated).
  final String? activityLabels;

  /// Event ID this photo belongs to (if clustered).
  final String? eventId;

  /// Version of the analysis pipeline that produced these results.
  final String analysisVersion;

  /// When this analysis was last computed.
  final DateTime? analyzedAt;

  /// What has been computed (bitmask of AnalysisStage).
  final int completedStages;

  const AnalysisState({
    required this.photoId,
    this.contentHash,
    this.perceptualHash,
    this.blurClassification = BlurClassification.unknown,
    this.exposureClassification = ExposureClassification.unknown,
    this.qualityScore,
    this.isScreenshot,
    this.isDocument,
    this.sceneLabels,
    this.activityLabels,
    this.eventId,
    this.analysisVersion = '1.0',
    this.analyzedAt,
    this.completedStages = 0,
  });

  /// Whether content hash has been computed.
  bool get hasContentHash => contentHash != null && contentHash!.isNotEmpty;

  /// Whether perceptual hash has been computed.
  bool get hasPerceptualHash =>
      perceptualHash != null && perceptualHash!.isNotEmpty;

  /// Whether quality analysis has been computed.
  bool get hasQualityAnalysis => qualityScore != null;

  /// Whether screenshot detection has been computed.
  bool get hasScreenshotDetection => isScreenshot != null;

  /// Whether document detection has been computed.
  bool get hasDocumentDetection => isDocument != null;

  /// Whether scene analysis has been computed.
  bool get hasSceneAnalysis => sceneLabels != null;

  /// Whether event clustering has been applied.
  bool get hasEventClustering => eventId != null;

  /// Check if a specific analysis stage is complete.
  bool hasStage(AnalysisStage stage) => (completedStages & stage.mask) != 0;

  /// Mark a stage as complete.
  AnalysisState withStage(AnalysisStage stage) => AnalysisState(
        photoId: photoId,
        contentHash: contentHash,
        perceptualHash: perceptualHash,
        blurClassification: blurClassification,
        exposureClassification: exposureClassification,
        qualityScore: qualityScore,
        isScreenshot: isScreenshot,
        isDocument: isDocument,
        sceneLabels: sceneLabels,
        activityLabels: activityLabels,
        eventId: eventId,
        analysisVersion: analysisVersion,
        analyzedAt: analyzedAt ?? DateTime.now(),
        completedStages: completedStages | stage.mask,
      );

  /// Check if this analysis needs recomputation for a given pipeline version.
  bool needsReanalysis(String currentVersion) =>
      analysisVersion != currentVersion;

  AnalysisState copyWith({
    String? contentHash,
    String? perceptualHash,
    BlurClassification? blurClassification,
    ExposureClassification? exposureClassification,
    double? qualityScore,
    bool? isScreenshot,
    bool? isDocument,
    String? sceneLabels,
    String? activityLabels,
    String? eventId,
    String? analysisVersion,
    DateTime? analyzedAt,
    int? completedStages,
  }) {
    return AnalysisState(
      photoId: photoId,
      contentHash: contentHash ?? this.contentHash,
      perceptualHash: perceptualHash ?? this.perceptualHash,
      blurClassification: blurClassification ?? this.blurClassification,
      exposureClassification:
          exposureClassification ?? this.exposureClassification,
      qualityScore: qualityScore ?? this.qualityScore,
      isScreenshot: isScreenshot ?? this.isScreenshot,
      isDocument: isDocument ?? this.isDocument,
      sceneLabels: sceneLabels ?? this.sceneLabels,
      activityLabels: activityLabels ?? this.activityLabels,
      eventId: eventId ?? this.eventId,
      analysisVersion: analysisVersion ?? this.analysisVersion,
      analyzedAt: analyzedAt ?? this.analyzedAt,
      completedStages: completedStages ?? this.completedStages,
    );
  }

  Map<String, Object?> toMap() => {
        'photo_id': photoId,
        'content_hash': contentHash,
        'perceptual_hash': perceptualHash,
        'blur_classification': blurClassification.index,
        'exposure_classification': exposureClassification.index,
        'quality_score': qualityScore,
        'is_screenshot': isScreenshot == null
            ? null
            : (isScreenshot! ? 1 : 0),
        'is_document':
            isDocument == null ? null : (isDocument! ? 1 : 0),
        'scene_labels': sceneLabels,
        'activity_labels': activityLabels,
        'event_id': eventId,
        'analysis_version': analysisVersion,
        'analyzed_at': analyzedAt?.toIso8601String(),
        'completed_stages': completedStages,
      };

  factory AnalysisState.fromMap(Map<String, Object?> row) => AnalysisState(
        photoId: row['photo_id'] as String,
        contentHash: row['content_hash'] as String?,
        perceptualHash: row['perceptual_hash'] as String?,
        blurClassification:
            BlurClassification.values[row['blur_classification'] as int? ?? 0],
        exposureClassification: ExposureClassification
            .values[row['exposure_classification'] as int? ?? 0],
        qualityScore: row['quality_score'] as double?,
        isScreenshot: row['is_screenshot'] == null
            ? null
            : (row['is_screenshot'] as int) == 1,
        isDocument:
            row['is_document'] == null ? null : (row['is_document'] as int) == 1,
        sceneLabels: row['scene_labels'] as String?,
        activityLabels: row['activity_labels'] as String?,
        eventId: row['event_id'] as String?,
        analysisVersion: row['analysis_version'] as String? ?? '1.0',
        analyzedAt: row['analyzed_at'] != null
            ? DateTime.parse(row['analyzed_at'] as String)
            : null,
        completedStages: row['completed_stages'] as int? ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalysisState &&
          runtimeType == other.runtimeType &&
          photoId == other.photoId;

  @override
  int get hashCode => photoId.hashCode;
}

/// Blur classification levels.
enum BlurClassification {
  unknown,
  clear,
  slightlyBlurry,
  blurry,
  veryBlurry,
}

/// Exposure classification levels.
enum ExposureClassification {
  unknown,
  underexposed,
  slightlyUnderexposed,
  balanced,
  slightlyOverexposed,
  overexposed,
}

/// Analysis pipeline stages (bitmask for tracking completed stages).
enum AnalysisStage {
  contentHash(1),
  perceptualHash(2),
  qualityAnalysis(4),
  blurDetection(8),
  exposureAnalysis(16),
  screenshotDetection(32),
  documentDetection(64),
  sceneAnalysis(128),
  activityAnalysis(256),
  eventClustering(512);

  const AnalysisStage(this.mask);
  final int mask;
}
