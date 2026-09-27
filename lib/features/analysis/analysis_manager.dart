import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/database/app_database.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/analysis_state.dart';
import '../../domain/models/ai_job.dart';
import 'services/duplicate_detection_service.dart';
import 'services/event_clustering_service.dart';
import 'services/quality_engine.dart';
import 'services/hash_service.dart';
import 'services/screenshot_detector.dart';
import 'services/document_detector.dart';
import 'services/video_analysis_service.dart';

/// Orchestrates all Phase 22 photo understanding and analysis services.
///
/// This manager:
/// 1. Runs incremental analysis on new/updated photos
/// 2. Manages analysis state (what's been computed)
/// 3. Coordinates duplicate detection, event clustering, quality analysis
/// 4. Provides a clean interface for the rest of the app
class AnalysisManager {
  AnalysisManager({
    required AppDatabase database,
    AppLogger? logger,
  })  : _database = database,
        _logger = logger {
    _duplicateService = DuplicateDetectionService(
      analysisDao: database.analysisState,
      duplicateDao: database.duplicates,
      logger: logger,
    );
    _eventService = EventClusteringService(
      analysisDao: database.analysisState,
      eventDao: database.events,
      logger: logger,
    );
    _videoAnalysisService = VideoAnalysisService(
      database: database,
      logger: logger ?? ConsoleAppLogger(),
    );
  }

  final AppDatabase _database;
  final AppLogger? _logger;
  final HashService _hashService = HashService();
  final QualityEngine _qualityEngine = QualityEngine();
  final ScreenshotDetector _screenshotDetector = ScreenshotDetector();
  final DocumentDetector _documentDetector = DocumentDetector();
  late final DuplicateDetectionService _duplicateService;
  late final EventClusteringService _eventService;
  late final VideoAnalysisService _videoAnalysisService;

  /// Current analysis pipeline version.
  /// Increment when analysis logic changes to trigger reanalysis.
  static const currentVersion = '1.0';

  /// Analyze a single photo — computes all applicable analysis stages.
  ///
  /// This is incremental: stages that have already been computed
  /// (at the current version) are skipped.
  Future<AnalysisState> analyzePhoto(String photoId, String filePath) async {
    // Get or create analysis state
    var state = await _database.analysisState.getByPhotoId(photoId);
    state ??= AnalysisState(
      photoId: photoId,
      analysisVersion: currentVersion,
    );

    // Skip stages already computed at current version
    if (!state.needsReanalysis(currentVersion) &&
        state.completedStages == AnalysisStage.values.fold<int>(0, (s, e) => s | e.mask)) {
      return state;
    }

    final file = File(filePath);
    if (!await file.exists()) return state;

    // Stage 1: Content hash
    if (!state.hasStage(AnalysisStage.contentHash)) {
      final hash = await _hashService.computeContentHash(filePath);
      state = state.copyWith(contentHash: hash);
      state = state.withStage(AnalysisStage.contentHash);
    }

    // Stage 2: Perceptual hash
    if (!state.hasStage(AnalysisStage.perceptualHash)) {
      final pHash = await _hashService.computePerceptualHash(filePath);
      state = state.copyWith(perceptualHash: pHash);
      state = state.withStage(AnalysisStage.perceptualHash);
    }

    // Decode image for pixel-level analysis
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);

    if (image != null) {
      final gray = _toGrayscale(image);

      // Stage 3-5: Quality analysis (blur, exposure, quality score)
      if (!state.hasStage(AnalysisStage.qualityAnalysis) ||
          !state.hasStage(AnalysisStage.blurDetection) ||
          !state.hasStage(AnalysisStage.exposureAnalysis)) {
        final quality = _qualityEngine.analyze(gray, image.width, image.height);
        state = state.copyWith(
          blurClassification: quality.blurClassification,
          exposureClassification: quality.exposureClassification,
          qualityScore: quality.qualityScore,
        );
        state = state
            .withStage(AnalysisStage.blurDetection)
            .withStage(AnalysisStage.exposureAnalysis)
            .withStage(AnalysisStage.qualityAnalysis);
      }

      // Stage 6: Screenshot detection
      if (!state.hasStage(AnalysisStage.screenshotDetection)) {
        final screenshotScore = await _screenshotDetector.detectScreenshot(filePath);
        state = state.copyWith(isScreenshot: screenshotScore > 0.6);
        state = state.withStage(AnalysisStage.screenshotDetection);
      }

      // Stage 7: Document detection
      if (!state.hasStage(AnalysisStage.documentDetection)) {
        final docScore = await _documentDetector.detectDocument(filePath);
        state = state.copyWith(isDocument: docScore > 0.6);
        state = state.withStage(AnalysisStage.documentDetection);
      }
    }

    // Update analysis version and timestamp
    state = state.copyWith(
      analysisVersion: currentVersion,
      analyzedAt: DateTime.now(),
    );

    // Persist
    await _database.analysisState.upsert(state);

    return state;
  }

  /// Run duplicate detection across the entire library.
  Future<DuplicateReport> findAllDuplicates() async {
    return _duplicateService.findAllDuplicates();
  }

  /// Run event clustering across the entire library.
  Future<int> clusterEvents() async {
    return _eventService.clusterAll();
  }

  /// Analyze a video: extract frames, detect segments, create analysis record.
  /// Returns the VideoAnalysis object.
  Future<dynamic> analyzeVideo(String videoId) async {
    return _videoAnalysisService.analyzeVideo(videoId);
  }

  /// Queue AI jobs for video frame analysis (OCR, faces, objects).
  /// Should be called after analyzeVideo completes.
  Future<void> queueVideoFrameJobs(String videoId) async {
    final frames = await _database.videoFrames.getByVideoId(videoId);
    if (frames.isEmpty) return;

    // Dedup: check if we already have queued/running jobs for this video
    final existing = await _database.aiJobs.getByPhotoId(videoId);
    final existingTypes = existing.map((j) => j.type).toSet();

    for (final frame in frames) {
      final frameJobId = '${videoId}_frame_${frame.id}';

      if (!existingTypes.contains(AIJobType.videoFrameOcr)) {
        await _database.aiJobs.upsert(AIJob(
          id: '${frameJobId}_ocr',
          type: AIJobType.videoFrameOcr,
          status: AIJobStatus.pending,
          photoId: videoId,
          createdAt: DateTime.now(),
        ));
      }

      if (!existingTypes.contains(AIJobType.videoFrameFaceDetection)) {
        await _database.aiJobs.upsert(AIJob(
          id: '${frameJobId}_face',
          type: AIJobType.videoFrameFaceDetection,
          status: AIJobStatus.pending,
          photoId: videoId,
          createdAt: DateTime.now(),
        ));
      }

      if (!existingTypes.contains(AIJobType.videoFrameObjectDetection)) {
        await _database.aiJobs.upsert(AIJob(
          id: '${frameJobId}_obj',
          type: AIJobType.videoFrameObjectDetection,
          status: AIJobStatus.pending,
          photoId: videoId,
          createdAt: DateTime.now(),
        ));
      }
    }

    _logger?.info('Queued frame analysis jobs for video $videoId (${frames.length} frames)');
  }

  /// Get analysis progress (fraction of photos analyzed).
  Future<AnalysisProgress> getProgress() async {
    final totalResult = await _database.database.rawQuery(
      'SELECT COUNT(*) as c FROM photos',
    );
    final total = totalResult.first['c'] as int? ?? 0;

    final analyzed = await _database.analysisState.countAnalyzed();

    final duplicateGroups = await _database.duplicates.count();

    final eventCount = await _database.events.count();

    // Video stats
    final videoCount = await _database.database.rawQuery(
      "SELECT COUNT(*) as c FROM photo_metadata WHERE media_type = 'video'",
    );
    final videoAnalyzed = await _database.videoAnalysis.countAnalyzed();
    final videoSegmentsCount = await _database.videoSegments.count();

    return AnalysisProgress(
      totalPhotos: total,
      analyzedPhotos: analyzed,
      duplicateGroups: duplicateGroups,
      eventCount: eventCount,
      totalVideos: videoCount.first['c'] as int? ?? 0,
      analyzedVideos: videoAnalyzed,
      videoSegments: videoSegmentsCount,
    );
  }

  /// Convert an image to grayscale pixel array.
  Uint8List _toGrayscale(img.Image image) {
    final gray = Uint8List(image.width * image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // ITU-R BT.601
        gray[y * image.width + x] =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
      }
    }
    return gray;
  }
}

/// Overall analysis progress across the library.
class AnalysisProgress {
  final int totalPhotos;
  final int analyzedPhotos;
  final int duplicateGroups;
  final int eventCount;
  final int totalVideos;
  final int analyzedVideos;
  final int videoSegments;

  const AnalysisProgress({
    required this.totalPhotos,
    required this.analyzedPhotos,
    required this.duplicateGroups,
    required this.eventCount,
    this.totalVideos = 0,
    this.analyzedVideos = 0,
    this.videoSegments = 0,
  });

  double get fractionAnalyzed =>
      totalPhotos > 0 ? analyzedPhotos / totalPhotos : 0.0;

  bool get isComplete => analyzedPhotos >= totalPhotos;
}
