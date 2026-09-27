import 'dart:io';
import 'dart:typed_data';

import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/ai/providers/face_detection_provider.dart';
import 'package:ai_gallery/ai/providers/object_detection_provider.dart';
import 'package:ai_gallery/domain/models/ai_job.dart';
import 'package:ai_gallery/domain/models/embedding.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';
import 'package:ai_gallery/domain/models/image_analysis.dart';
import 'package:ai_gallery/domain/models/object_detection_model.dart';
import 'package:ai_gallery/domain/models/object_detection.dart';
import 'package:ai_gallery/domain/models/ocr.dart';
import '../../features/analysis/services/caption_generator.dart';
import 'package:ai_gallery/domain/models/photo_metadata.dart';
import 'package:ai_gallery/domain/models/video_segment.dart';
import 'package:ai_gallery/domain/repositories/photo_repository.dart';
import 'package:ai_gallery/features/people/services/face_clustering_service.dart';
import 'package:image/image.dart' as img;

/// Callback type for reporting job progress.
typedef ProgressCallback = Future<void> Function(String jobId, double progress);

/// Shared AI job processing logic used by both AIManagerImpl and the background
/// worker isolate. This eliminates code duplication between the two.
class AIJobProcessor {
  AIJobProcessor({
    required this.database,
    required this.photoRepository,
    required this.logger,
    required this.embeddingProvider,
    required this.faceEmbeddingProvider,
    required this.objectDetectionProvider,
    required this.faceDetectionProvider,
    this.ocrProvider,
  });

  final AppDatabase database;
  final PhotoRepository photoRepository;
  final AppLogger logger;
  final EmbeddingProvider? embeddingProvider;
  final EmbeddingProvider? faceEmbeddingProvider;
  final ObjectDetectionProvider? objectDetectionProvider;
  final FaceDetectionProvider? faceDetectionProvider;
  final ObjectDetectionProvider? ocrProvider;

  FaceClusteringService? _faceClusteringService;

  FaceClusteringService _getFaceClusteringService() {
    _faceClusteringService ??= FaceClusteringService(
      logger: logger,
      database: database,
    );
    return _faceClusteringService!;
  }

  /// Process a job of any type.
  Future<void> processJob(AIJob job, ProgressCallback onProgress) async {
    switch (job.type) {
      case AIJobType.embedding:
        await _processEmbedding(job, onProgress);
      case AIJobType.faceDetection:
        await _processFaceDetection(job, onProgress);
      case AIJobType.faceEmbedding:
        await _processFaceEmbedding(job, onProgress);
      case AIJobType.objectTagging:
        await _processObjectTagging(job, onProgress);
      case AIJobType.regionEmbedding:
        await _processRegionEmbedding(job, onProgress);
      case AIJobType.ocr:
        await _processOcr(job, onProgress);
      case AIJobType.caption:
        await _processCaption(job, onProgress);
      case AIJobType.videoFrameOcr:
        await _processVideoFrameOcr(job, onProgress);
      case AIJobType.videoFrameFaceDetection:
        await _processVideoFrameFaceDetection(job, onProgress);
      case AIJobType.videoFrameObjectDetection:
        await _processVideoFrameObjectDetection(job, onProgress);
      case AIJobType.videoAnalysis:
      case AIJobType.videoFrameExtraction:
        logger.info('Job type ${job.type.name} handled by video pipeline');
      case AIJobType.videoEmbedding:
        await _processVideoEmbedding(job, onProgress);
    }
  }

  // ─────────────────────────────────────────────
  // Embedding Processing
  // ─────────────────────────────────────────────

  Future<void> _processEmbedding(AIJob job, ProgressCallback onProgress) async {
    if (embeddingProvider == null) {
      throw StateError('No embedding provider available');
    }

    await onProgress(job.id, 0.1);

    final imageBytes = await photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }

    await onProgress(job.id, 0.3);

    final Float32List embedding = await embeddingProvider!.generateEmbedding(
      imageBytes,
    );

    await onProgress(job.id, 0.7);

    await _saveEmbedding(job.photoId, embedding);

    await onProgress(job.id, 1.0);
  }

  // ─────────────────────────────────────────────
  // Face Detection Processing
  // ─────────────────────────────────────────────

  Future<void> _processFaceDetection(
    AIJob job,
    ProgressCallback onProgress,
  ) async {
    if (faceDetectionProvider == null) {
      logger.warning('Face detection provider not available, skipping');
      return;
    }

    await onProgress(job.id, 0.1);

    final photoMetadata = await database.photoMetadata.getById(job.photoId);
    if (photoMetadata != null) {
      final currentFaceModelVersion =
          '${faceDetectionProvider?.id ?? 'unknown'}_v1';
      if (photoMetadata.faceStatus == FaceStatus.completed &&
          photoMetadata.faceModelVersion == currentFaceModelVersion) {
        logger.info(
          'Face detection already completed for photo ${job.photoId} with model version $currentFaceModelVersion, skipping',
        );
        await onProgress(job.id, 1.0);
        return;
      }

      final updatedMetadata = photoMetadata.copyWith(
        faceStatus: FaceStatus.processing,
        faceModelVersion: currentFaceModelVersion,
      );
      await database.photoMetadata.upsert(updatedMetadata);
    }

    final imageBytes = await photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      logger.warning('Failed to load image bytes for photo ${job.photoId}');
      if (photoMetadata != null) {
        final updatedMetadata = photoMetadata.copyWith(
          faceStatus: FaceStatus.failed,
        );
        await database.photoMetadata.upsert(updatedMetadata);
      }
      await _saveFaceDetections(job.photoId, <FaceDetection>[]);
      await onProgress(job.id, 1.0);
      return;
    }

    await onProgress(job.id, 0.3);

    final faces = await faceDetectionProvider!.detectFaces(imageBytes);

    if (faces.isEmpty) {
      await database.faces.deleteFacesByPhotoId(job.photoId);
      await _saveFaceDetections(job.photoId, faces);
      if (photoMetadata != null) {
        final updatedMetadata = photoMetadata.copyWith(
          faceStatus: FaceStatus.noFaces,
        );
        await database.photoMetadata.upsert(updatedMetadata);
      }
      await onProgress(job.id, 1.0);
      return;
    }

    await onProgress(job.id, 0.7);

    await database.faces.deleteFacesByPhotoId(job.photoId);
    await _saveFaceDetections(job.photoId, faces);

    if (photoMetadata != null) {
      final updatedMetadata = photoMetadata.copyWith(
        faceStatus: FaceStatus.completed,
      );
      await database.photoMetadata.upsert(updatedMetadata);
    }

    await onProgress(job.id, 1.0);
  }

  // ─────────────────────────────────────────────
  // Face Embedding Processing
  // ─────────────────────────────────────────────

  Future<void> _processFaceEmbedding(
    AIJob job,
    ProgressCallback onProgress,
  ) async {
    if (faceDetectionProvider == null || faceEmbeddingProvider == null) {
      logger.warning(
        'Face detection/embedding providers not available, skipping',
      );
      return;
    }

    await onProgress(job.id, 0.1);

    // Dedup: if faces for this photo already have embeddings, skip reprocessing.
    // We deliberately do NOT touch faceStatus/faceModelVersion here because
    // those track Face *Detection* (a separate job). Overwriting them with the
    // embedding model's id would cause the detection job to re-run needlessly
    // on every queue cycle (version mismatch ping-pong).
    //
    // Tiny faces are deliberately stored WITHOUT embeddings (their aligned
    // crops are too small for reliable recognition), so they don't count as
    // pending either.
    final existingFaces = await database.faces.getFacesByPhotoId(job.photoId);
    final needsEmbedding = existingFaces.where(
      (f) => f.embedding == null && !_isTinyFaceBox(f.width, f.height),
    );
    if (existingFaces.isNotEmpty && needsEmbedding.isEmpty) {
      logger.info(
        'Face embedding already completed for photo ${job.photoId}, skipping',
      );
      await onProgress(job.id, 1.0);
      return;
    }

    final imageBytes = await photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      logger.warning('Failed to load image bytes for photo ${job.photoId}');
      await onProgress(job.id, 1.0);
      return;
    }

    await onProgress(job.id, 0.2);

    final detected = await faceDetectionProvider!.detectFaces(imageBytes);
    if (detected.isEmpty) {
      logger.info('No faces detected for face embedding');
      // Detection job owns faceStatus; nothing for us to persist here.
      await onProgress(job.id, 1.0);
      return;
    }

    // Drop near-duplicate boxes (same face detected twice) keeping the
    // highest-confidence box — duplicates otherwise pollute clusters.
    final faces = _dedupeOverlappingFaces(detected);

    await onProgress(job.id, 0.4);

    logger.info('Detected ${faces.length} faces for embedding generation');

    final faceRecords = <FaceDetectionRecord>[];
    bool allEmbeddingsSuccessful = true;

    for (var i = 0; i < faces.length; i++) {
      final face = faces[i];
      await onProgress(job.id, 0.5 + (0.4 * i / faces.length));

      if (_isTinyFaceBox(face.width, face.height)) {
        // Keep the detection (person presence still counts) but skip the
        // embedding: upscaling a <0.2%-area crop to 112px yields noise that
        // degrades clustering for everyone else.
        logger.info('Skipping embedding for tiny face $i in photo ${job.photoId}');
        faceRecords.add(
          FaceDetectionRecord(
            id: '${job.photoId}_$i',
            photoId: job.photoId,
            x: face.x,
            y: face.y,
            width: face.width,
            height: face.height,
            confidence: face.confidence,
            label: null,
            embedding: null,
          ),
        );
        continue;
      }

      try {
        final embedding = await faceEmbeddingProvider!
            .generateEmbeddingFromFace(
              imageBytes: imageBytes,
              faceDetection: face,
            );

        faceRecords.add(
          FaceDetectionRecord(
            id: '${job.photoId}_$i',
            photoId: job.photoId,
            x: face.x,
            y: face.y,
            width: face.width,
            height: face.height,
            confidence: face.confidence,
            label: null,
            embedding: embedding,
          ),
        );
      } catch (e, st) {
        logger.error(
          'Failed to generate embedding for face $i',
          error: e,
          stackTrace: st,
        );
        allEmbeddingsSuccessful = false;
        break;
      }
    }

    if (!allEmbeddingsSuccessful) {
      logger.warning(
        'Face embedding generation failed for photo ${job.photoId}',
      );
      // Don't reset faceStatus to failed: detection already succeeded and
      // faceStatus tracks detection. Embedding failure is logged; clustering
      // will be retried on the next embedding job run.
      await onProgress(job.id, 1.0);
      return;
    }

    await database.faces.deleteFacesByPhotoId(job.photoId);
    await onProgress(job.id, 0.9);
    await database.faces.insertFaces(faceRecords);

    final clusteringService = _getFaceClusteringService();
    for (final faceRecord in faceRecords) {
      if (faceRecord.embedding != null) {
        try {
          await clusteringService.clusterFace(faceRecord);
        } catch (e, st) {
          logger.error(
            'Failed to auto-cluster face ${faceRecord.id}',
            error: e,
            stackTrace: st,
          );
        }
      }
    }

    // faceStatus/faceModelVersion are managed by the detection job. The
    // successful embedding step only needs to persist the face records with
    // embeddings (done above), used downstream by clustering.

    await onProgress(job.id, 1.0);
  }

  // ─────────────────────────────────────────────
  // Object Tagging Processing
  // ─────────────────────────────────────────────

  Future<void> _processObjectTagging(
    AIJob job,
    ProgressCallback onProgress,
  ) async {
    await onProgress(job.id, 0.1);

    final imageBytes = await photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }

    await onProgress(job.id, 0.3);

    final objProvider = objectDetectionProvider;
    final objects = objProvider != null
        ? (await objProvider.detectObjects(imageBytes)).detections
        : <DetectedObject>[];

    await onProgress(job.id, 0.7);

    await _saveObjectDetections(job.photoId, objects);

    await onProgress(job.id, 1.0);
  }

  // ─────────────────────────────────────────────
  // Region Embedding Processing
  // ─────────────────────────────────────────────

  /// Maximum object crops embedded per photo (bounds indexing cost).
  static const int _maxRegionsPerPhoto = 3;

  /// Minimum detection confidence for a crop to earn its own embedding.
  static const double _minRegionConfidence = 0.5;

  /// Minimum crop area (fraction of photo) to embed.
  static const double _minRegionArea = 0.02;

  /// Embed the most prominent detected-object crops of a photo.
  ///
  /// Gives small/background objects in complex scenes their own vectors so
  /// semantic search can match them directly instead of relying on the single
  /// whole-photo embedding. Reads saved object tags (no detector needed) and
  /// skips photos whose regions are already embedded.
  Future<void> _processRegionEmbedding(
    AIJob job,
    ProgressCallback onProgress,
  ) async {
    if (embeddingProvider == null) {
      throw StateError('No embedding provider available');
    }

    await onProgress(job.id, 0.1);

    final existing = await database.embeddings.countRegionsByPhotoId(job.photoId);
    if (existing > 0) {
      logger.info('Region embeddings already exist for photo ${job.photoId}, skipping');
      await onProgress(job.id, 1.0);
      return;
    }

    final tags = await database.objectTags.getObjectTagsByPhotoId(job.photoId);
    final eligible = tags
        .where((t) =>
            t.confidence >= _minRegionConfidence &&
            (t.boundingBoxWidth * t.boundingBoxHeight) >= _minRegionArea)
        .toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = eligible.take(_maxRegionsPerPhoto).toList();
    if (selected.isEmpty) {
      await onProgress(job.id, 1.0);
      return;
    }

    final imageBytes = await photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw StateError('Failed to decode image for photo ${job.photoId}');
    }

    await onProgress(job.id, 0.3);

    final modelId = embeddingProvider!.modelId;
    var done = 0;
    for (var i = 0; i < selected.length; i++) {
      final tag = selected[i];
      try {
        final crop = _cropWithPadding(decoded, tag);
        if (crop == null) continue;
        final cropBytes = Uint8List.fromList(img.encodeJpg(crop, quality: 85));
        final vector = await embeddingProvider!.generateEmbedding(cropBytes);
        await database.embeddings.insertEmbedding(EmbeddingRecord(
          id: '${job.photoId}_region_$i',
          photoId: job.photoId,
          vector: vector,
          modelId: modelId,
          dimensions: vector.length,
          regionLabel: tag.label,
          regionBboxLeft: tag.boundingBoxLeft,
          regionBboxTop: tag.boundingBoxTop,
          regionBboxWidth: tag.boundingBoxWidth,
          regionBboxHeight: tag.boundingBoxHeight,
        ));
        done++;
      } catch (e) {
        logger.warning('Region embedding failed for ${job.photoId} region $i', error: e);
      }
      await onProgress(job.id, 0.3 + 0.6 * ((i + 1) / selected.length));
    }

    logger.info('Embedded $done/${selected.length} regions for photo ${job.photoId}');
    await onProgress(job.id, 1.0);
  }

  /// Minimum face area (fraction of frame) worth embedding.
  ///
  /// Below this, the eye-aligned 112px crop is mostly upscaling noise and the
  /// resulting vector harms cluster purity more than the extra sample helps.
  static const double _minFaceArea = 0.002;

  /// IoU above which two face boxes are considered the same face.
  static const double _faceDedupeIou = 0.5;

  static bool _isTinyFaceBox(double width, double height) =>
      width * height < _minFaceArea;

  /// Remove near-duplicate face boxes, keeping the highest-confidence box
  /// per overlapping group.
  static List<FaceDetection> _dedupeOverlappingFaces(List<FaceDetection> faces) {
    final sorted = faces.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <FaceDetection>[];
    for (final face in sorted) {
      final overlaps = kept.any((k) => _iou(face, k) > _faceDedupeIou);
      if (!overlaps) kept.add(face);
    }
    return kept;
  }

  static double _iou(FaceDetection a, FaceDetection b) {
    final left = a.x > b.x ? a.x : b.x;
    final top = a.y > b.y ? a.y : b.y;
    final right = a.x + a.width < b.x + b.width ? a.x + a.width : b.x + b.width;
    final bottom = a.y + a.height < b.y + b.height ? a.y + a.height : b.y + b.height;
    final inter = (right - left) * (bottom - top);
    if (inter <= 0) return 0.0;
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0.0 : inter / union;
  }

  /// Crop a detection box with 10% padding, clamped to the image bounds.
  /// Returns null when the box is degenerate.
  img.Image? _cropWithPadding(img.Image decoded, ObjectTagRecord tag) {
    final w = decoded.width;
    final h = decoded.height;
    final padX = tag.boundingBoxWidth * 0.1;
    final padY = tag.boundingBoxHeight * 0.1;
    final left = ((tag.boundingBoxLeft - padX) * w).round().clamp(0, w - 1);
    final top = ((tag.boundingBoxTop - padY) * h).round().clamp(0, h - 1);
    final right = ((tag.boundingBoxLeft + tag.boundingBoxWidth + padX) * w).round().clamp(1, w);
    final bottom = ((tag.boundingBoxTop + tag.boundingBoxHeight + padY) * h).round().clamp(1, h);
    final cw = right - left;
    final ch = bottom - top;
    if (cw < 8 || ch < 8) return null;
    return img.copyCrop(decoded, x: left, y: top, width: cw, height: ch);
  }

  // ─────────────────────────────────────────────
  // OCR Processing
  // ─────────────────────────────────────────────

  Future<void> _processOcr(AIJob job, ProgressCallback onProgress) async {
    final provider = ocrProvider ?? objectDetectionProvider;
    if (provider == null) {
      logger.warning('OCR provider not available, skipping');
      await _saveOcrResult(job.photoId, '', 0.0, null, null, null, null);
      await onProgress(job.id, 1.0);
      return;
    }

    await onProgress(job.id, 0.1);

    final photoMetadata = await database.photoMetadata.getById(job.photoId);
    if (photoMetadata != null) {
      final currentOcrModelVersion = '${provider.id}_v1';
      if (photoMetadata.ocrStatus == OcrStatus.completed &&
          photoMetadata.ocrModelVersion == currentOcrModelVersion) {
        logger.info(
          'OCR already completed for photo ${job.photoId} with model version $currentOcrModelVersion, skipping',
        );
        await onProgress(job.id, 1.0);
        return;
      }

      final updatedMetadata = photoMetadata.copyWith(
        ocrStatus: OcrStatus.processing,
        ocrModelVersion: currentOcrModelVersion,
      );
      await database.photoMetadata.upsert(updatedMetadata);
    }

    final imageBytes = await photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      logger.warning('Failed to load image bytes for photo ${job.photoId}');
      await _saveOcrResult(job.photoId, '', 0.0, null, null, null, null);
      if (photoMetadata != null) {
        final updatedMetadata = photoMetadata.copyWith(
          ocrStatus: OcrStatus.failed,
        );
        await database.photoMetadata.upsert(updatedMetadata);
      }
      await onProgress(job.id, 1.0);
      return;
    }

    await onProgress(job.id, 0.2);

    final result = await provider.detectObjects(imageBytes);

    await onProgress(job.id, 0.7);

    if (result.detections.isEmpty) {
      await _saveOcrResult(job.photoId, '', 0.0, null, null, null, null);
      if (photoMetadata != null) {
        final updatedMetadata = photoMetadata.copyWith(
          ocrStatus: OcrStatus.noText,
        );
        await database.photoMetadata.upsert(updatedMetadata);
      }
      await onProgress(job.id, 1.0);
      return;
    }

    final allText = result.detections.map((d) => d.label).join('\n').trim();

    final double avgConfidence = result.detections.isNotEmpty
        ? result.detections.map((d) => d.confidence).reduce((a, b) => a + b) /
              result.detections.length
        : 0.0;

    double? combinedLeft;
    double? combinedTop;
    double? combinedWidth;
    double? combinedHeight;

    if (result.detections.isNotEmpty) {
      final List<List<double>> ltrbBoxes = result.detections
          .map((det) => det.boundingBoxLTRB)
          .toList();

      final double minLeft = ltrbBoxes
          .map((box) => box[0])
          .reduce((a, b) => a < b ? a : b);
      final double minTop = ltrbBoxes
          .map((box) => box[1])
          .reduce((a, b) => a < b ? a : b);
      final double maxRight = ltrbBoxes
          .map((box) => box[2])
          .reduce((a, b) => a > b ? a : b);
      final double maxBottom = ltrbBoxes
          .map((box) => box[3])
          .reduce((a, b) => a > b ? a : b);

      final double combinedL = minLeft.clamp(0.0, 1.0);
      final double combinedT = minTop.clamp(0.0, 1.0);
      final double combinedR = maxRight.clamp(0.0, 1.0);
      final double combinedB = maxBottom.clamp(0.0, 1.0);

      combinedLeft = combinedL;
      combinedTop = combinedT;
      combinedWidth = (combinedR - combinedL).clamp(0.0, 1.0);
      combinedHeight = (combinedB - combinedT).clamp(0.0, 1.0);
    }

    await _saveOcrResult(
      job.photoId,
      allText,
      avgConfidence,
      combinedLeft,
      combinedTop,
      combinedWidth,
      combinedHeight,
    );

    if (photoMetadata != null) {
      final updatedMetadata = photoMetadata.copyWith(
        ocrStatus: OcrStatus.completed,
      );
      await database.photoMetadata.upsert(updatedMetadata);
    }

    await onProgress(job.id, 1.0);
  }

  // ─────────────────────────────────────────────
  // Caption Processing
  // ─────────────────────────────────────────────

  Future<void> _processCaption(AIJob job, ProgressCallback onProgress) async {
    await onProgress(job.id, 0.1);

    // Generate caption from existing metadata (scene labels, objects, people, camera)
    final captionGenerator = CaptionGenerator(database);
    final caption = await captionGenerator.generateCaption(job.photoId);

    // Log the generated caption (no dedicated caption column in DB yet)
    logger.info('Generated caption for ${job.photoId}: $caption');

    await onProgress(job.id, 0.5);

    // Also generate embedding and quality analysis if provider available
    if (embeddingProvider != null) {
      final imageBytes = await photoRepository.getImageBytes(job.photoId);
      if (imageBytes != null) {
        final embedding = await embeddingProvider!.generateEmbedding(imageBytes);
        await _saveEmbedding(job.photoId, embedding);

        await onProgress(job.id, 0.7);

        final analysis = await analyzeImageQuality(imageBytes);
        await _saveImageAnalysis(job.photoId, analysis);
      }
    }

    await onProgress(job.id, 1.0);
  }

  // ─────────────────────────────────────────────
  // Image Quality Analysis
  // ─────────────────────────────────────────────

  /// Analyze image quality (blur, brightness, dominant colors).
  Future<ImageAnalysis> analyzeImageQuality(Uint8List imageBytes) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        return const ImageAnalysis();
      }

      var brightnessSum = 0;
      var totalPixels = 0;

      const sampleStep = 4;
      for (var y = 0; y < decoded.height; y += sampleStep) {
        for (var x = 0; x < decoded.width; x += sampleStep) {
          final pixel = decoded.getPixel(x, y);
          final luminance =
              (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
          brightnessSum += luminance;
          totalPixels++;
        }
      }

      final avgBrightness = totalPixels > 0
          ? brightnessSum / totalPixels / 255.0
          : 0.5;
      final isLowLight = avgBrightness < 0.3;

      var brightnessVarSum = 0.0;
      for (var y = 0; y < decoded.height; y += sampleStep) {
        for (var x = 0; x < decoded.width; x += sampleStep) {
          final pixel = decoded.getPixel(x, y);
          final luminance = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
          final diff = luminance - avgBrightness * 255;
          brightnessVarSum += diff * diff;
        }
      }
      final blurScore = totalPixels > 0 ? brightnessVarSum / totalPixels : 0.0;
      final isBlurry = blurScore < 100.0;

      final colorCounts = <String, int>{};
      final colorStepY = decoded.height ~/ 10;
      final colorStepX = decoded.width ~/ 10;
      if (colorStepY > 0 && colorStepX > 0) {
        for (var y = 0; y < decoded.height; y += colorStepY) {
          for (var x = 0; x < decoded.width; x += colorStepX) {
            final pixel = decoded.getPixel(x, y);
            final colorKey =
                '#${pixel.r.toInt().toRadixString(16).padLeft(2, '0')}${pixel.g.toInt().toRadixString(16).padLeft(2, '0')}${pixel.b.toInt().toRadixString(16).padLeft(2, '0')}';
            colorCounts[colorKey] = (colorCounts[colorKey] ?? 0) + 1;
          }
        }
      } else if (decoded.height > 0 && decoded.width > 0) {
        final pixel = decoded.getPixel(0, 0);
        final colorKey =
            '#${pixel.r.toInt().toRadixString(16).padLeft(2, '0')}${pixel.g.toInt().toRadixString(16).padLeft(2, '0')}${pixel.b.toInt().toRadixString(16).padLeft(2, '0')}';
        colorCounts[colorKey] = 1;
      }

      return ImageAnalysis(
        isBlurry: isBlurry,
        blurScore: blurScore,
        dominantColors: colorCounts,
        isLowLight: isLowLight,
        brightness: avgBrightness,
      );
    } catch (e) {
      return const ImageAnalysis();
    }
  }

  // ─────────────────────────────────────────────
  // Database Persistence Helpers
  // ─────────────────────────────────────────────

  Future<void> _saveEmbedding(String photoId, Float32List embedding) async {
    final provider = embeddingProvider;
    String modelId = 'unknown';
    if (provider != null) {
      modelId = provider.modelId;
    }

    final record = EmbeddingRecord(
      id: photoId,
      photoId: photoId,
      vector: embedding,
      modelId: modelId,
      dimensions: embedding.length,
    );
    await database.embeddings.insertEmbedding(record);
  }

  Future<void> _saveFaceDetections(
    String photoId,
    List<FaceDetection> faces, {
    String scopeSuffix = '',
  }) async {
    final prefix = scopeSuffix.isEmpty ? photoId : '${photoId}_$scopeSuffix';
    final records = faces
        .asMap()
        .entries
        .map(
          (entry) => FaceDetectionRecord(
            id: '${prefix}_${entry.key}',
            photoId: photoId,
            x: entry.value.x,
            y: entry.value.y,
            width: entry.value.width,
            height: entry.value.height,
            confidence: entry.value.confidence,
            label: entry.value.label,
            embedding: entry.value.embedding,
          ),
        )
        .toList();
    await database.faces.insertFaces(records);
  }

  Future<void> _saveObjectDetections(
    String photoId,
    List<DetectedObject> objects,
  ) async {
    final records = objects.asMap().entries.map((entry) {
      final bbox = entry.value.boundingBox;
      return ObjectTagRecord(
        id: '${photoId}_${entry.key}',
        photoId: photoId,
        label: entry.value.label,
        confidence: entry.value.confidence,
        boundingBoxLeft: (bbox[0] - bbox[2] / 2).clamp(0.0, 1.0),
        boundingBoxTop: (bbox[1] - bbox[3] / 2).clamp(0.0, 1.0),
        boundingBoxWidth: bbox[2].clamp(0.0, 1.0),
        boundingBoxHeight: bbox[3].clamp(0.0, 1.0),
      );
    }).toList();
    await database.objectTags.insertObjectTags(records);
  }

  Future<void> _saveOcrResult(
    String photoId,
    String text,
    double confidence,
    double? boundingBoxLeft,
    double? boundingBoxTop,
    double? boundingBoxWidth,
    double? boundingBoxHeight,
  ) async {
    final record = OcrRecord(
      id: photoId,
      photoId: photoId,
      text: text,
      confidence: confidence,
      boundingBoxLeft: boundingBoxLeft,
      boundingBoxTop: boundingBoxTop,
      boundingBoxWidth: boundingBoxWidth,
      boundingBoxHeight: boundingBoxHeight,
    );
    await database.ocrResults.insertOcr(record);
  }

  Future<void> _saveImageAnalysis(
    String photoId,
    ImageAnalysis analysis,
  ) async {
    final existing = await database.photoMetadata.getById(photoId);
    if (existing == null) return;

    final qualityScore = analysis.blurScore > 0.7 && analysis.brightness > 0.3
        ? 1.0
        : analysis.blurScore * 0.6 + (analysis.brightness > 0.3 ? 0.4 : 0.2);

    final updated = existing.copyWith(
      blurScore: analysis.blurScore,
      brightness: analysis.brightness,
      qualityScore: qualityScore,
    );
    await database.photoMetadata.upsert(updated);
  }

  // ─────────────────────────────────────────────
  // Video Frame Processing (Phase 25)
  // ─────────────────────────────────────────────

  /// Load a frame image from its saved path.
  Future<Uint8List?> _loadFrameImage(String framePath) async {
    try {
      final file = File(framePath);
      if (!await file.exists()) return null;
      return file.readAsBytes();
    } catch (e) {
      logger.warning('Failed to load frame image: $framePath', error: e);
      return null;
    }
  }

  Future<void> _processVideoFrameOcr(
    AIJob job,
    ProgressCallback onProgress,
  ) async {
    if (ocrProvider == null) {
      logger.warning('OCR provider not available for video frame processing');
      return;
    }

    final videoId = job.photoId;
    final frames = await database.videoFrames.getByVideoId(videoId);
    if (frames.isEmpty) return;

    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      await onProgress(job.id, i / frames.length);

      final imageBytes = await _loadFrameImage(frame.framePath);
      if (imageBytes == null) continue;

      try {
        final result = await ocrProvider!.detectObjects(imageBytes);
        if (result.detections.isEmpty) continue;

        final textParts = result.detections
            .where((d) => d.label.isNotEmpty)
            .map((d) => d.label)
            .toList();
        if (textParts.isEmpty) continue;

        final ocrText = textParts.join(' ');
        final confidence = result.detections
            .map((d) => d.confidence)
            .reduce((a, b) => a > b ? a : b);

        final segments = await database.videoSegments.getByVideoId(videoId);
        VideoSegment? nearest;
        var minDist = double.infinity;
        for (final seg in segments) {
          final dist = (seg.startTimeMs - frame.timestampMs).abs().toDouble();
          if (dist < minDist) {
            minDist = dist;
            nearest = seg;
          }
        }

        if (nearest != null) {
          final existingText = nearest.ocrText ?? '';
          final updated = nearest.copyWith(
            ocrText: existingText.isNotEmpty
                ? '$existingText $ocrText'
                : ocrText,
            confidence: confidence,
          );
          await database.videoSegments.upsert(updated);
        }
      } catch (e) {
        logger.warning('Video OCR failed for frame ${frame.id}', error: e);
      }
    }

    await onProgress(job.id, 1.0);
  }

  Future<void> _processVideoFrameFaceDetection(
    AIJob job,
    ProgressCallback onProgress,
  ) async {
    if (faceDetectionProvider == null) {
      logger.warning(
          'Face detection provider not available for video frame processing');
      return;
    }

    final videoId = job.photoId;
    final frames = await database.videoFrames.getByVideoId(videoId);
    if (frames.isEmpty) return;

    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      await onProgress(job.id, i / frames.length);

      final imageBytes = await _loadFrameImage(frame.framePath);
      if (imageBytes == null) continue;

      try {
        final faces = await faceDetectionProvider!.detectFaces(imageBytes);
        if (faces.isEmpty) continue;

        // Persist per-frame face records (scoped by frame id so each frame's
        // faces are stored distinctly). Face identity is resolved later during
        // person clustering; synthetic `face:N` tokens are NOT written to the
        // `people` column since the knowledge graph builder filters them out.
        await _saveFaceDetections(videoId, faces, scopeSuffix: frame.id);
      } catch (e) {
        logger.warning('Video face detection failed for frame ${frame.id}',
            error: e);
      }
    }

    await onProgress(job.id, 1.0);
  }

  Future<void> _processVideoFrameObjectDetection(
    AIJob job,
    ProgressCallback onProgress,
  ) async {
    if (objectDetectionProvider == null) {
      logger.warning(
          'Object detection provider not available for video frame processing');
      return;
    }

    final videoId = job.photoId;
    final frames = await database.videoFrames.getByVideoId(videoId);
    if (frames.isEmpty) return;

    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      await onProgress(job.id, i / frames.length);

      final imageBytes = await _loadFrameImage(frame.framePath);
      if (imageBytes == null) continue;

      try {
        final result =
            await objectDetectionProvider!.detectObjects(imageBytes);
        if (result.detections.isEmpty) continue;

        final labels = result.detections
            .where((d) => d.label.isNotEmpty)
            .map((d) => d.label)
            .toList();
        if (labels.isEmpty) continue;

        final segments = await database.videoSegments.getByVideoId(videoId);
        VideoSegment? nearest;
        var minDist = double.infinity;
        for (final seg in segments) {
          final dist = (seg.startTimeMs - frame.timestampMs).abs().toDouble();
          if (dist < minDist) {
            minDist = dist;
            nearest = seg;
          }
        }

        if (nearest != null) {
          final existingLabels = List<String>.from(nearest.labels);
          final newLabels =
              labels.where((l) => !existingLabels.contains(l)).toList();
          if (newLabels.isEmpty) continue;

          existingLabels.addAll(newLabels);
          final updated = nearest.copyWith(labels: existingLabels);
          await database.videoSegments.upsert(updated);
        }

        await _saveObjectDetections(videoId, result.detections);
      } catch (e) {
        logger.warning(
            'Video object detection failed for frame ${frame.id}',
            error: e);
      }
    }

    await onProgress(job.id, 1.0);
  }

  // ─────────────────────────────────────────────
  // Video Embedding Processing
  // ─────────────────────────────────────────────

  Future<void> _processVideoEmbedding(
    AIJob job,
    ProgressCallback onProgress,
  ) async {
    if (embeddingProvider == null) {
      logger.warning(
          'Embedding provider not available for video embedding');
      return;
    }

    final videoId = job.photoId;
    final frames = await database.videoFrames.getByVideoId(videoId);
    if (frames.isEmpty) return;

    // Cache segments once before the loop (avoids O(F×S) DB queries)
    final segments = await database.videoSegments.getByVideoId(videoId);

    // Track how many frame embeddings have contributed to each segment so the
    // running mean is computed correctly: newAvg = (avg * n + x) / (n + 1).
    // A naive (avg + x) / 2 over-weights the newest frame as n grows.
    final contributedFrames = <String, int>{};

    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      await onProgress(job.id, i / frames.length);

      final imageBytes = await _loadFrameImage(frame.framePath);
      if (imageBytes == null) continue;

      try {
        final embedding = await embeddingProvider!.generateEmbedding(
          imageBytes,
        );

        // Store embedding using frame ID as photo ID
        // so search can compare across video frames
        await _saveEmbedding(frame.id, embedding);

        // Also update the nearest segment's embedding field
        // (average of all frame embeddings in the segment)
        VideoSegment? nearest;
        var minDist = double.infinity;

        for (final seg in segments) {
          final dist =
              (seg.startTimeMs - frame.timestampMs).abs().toDouble();
          if (dist < minDist) {
            minDist = dist;
            nearest = seg;
          }
        }

        if (nearest != null) {
          final existingEmbedding = nearest.embedding;
          List<double> newEmbedding;
          if (existingEmbedding != null &&
              existingEmbedding.length == embedding.length) {
            final n = (contributedFrames[nearest.id] ?? 1);
            newEmbedding = List<double>.generate(
              embedding.length,
              (j) => (existingEmbedding[j] * n + embedding[j]) / (n + 1),
            );
            contributedFrames[nearest.id] = n + 1;
          } else {
            newEmbedding = embedding.toList();
            contributedFrames[nearest.id] = 1;
          }
          await database.videoSegments.upsert(
            nearest.copyWith(embedding: newEmbedding),
          );
        }
      } catch (e) {
        logger.warning(
          'Video embedding failed for frame ${frame.id}',
          error: e,
        );
      }
    }

    await onProgress(job.id, 1.0);
  }
}
