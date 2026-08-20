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
import 'package:ai_gallery/domain/models/photo_metadata.dart';
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
      case AIJobType.ocr:
        await _processOcr(job, onProgress);
      case AIJobType.caption:
        await _processCaption(job, onProgress);
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

    final photoMetadata = await database.photoMetadata.getById(job.photoId);
    if (photoMetadata != null) {
      final currentFaceModelVersion =
          '${faceEmbeddingProvider?.id ?? 'unknown'}_v1';
      if (photoMetadata.faceStatus == FaceStatus.completed &&
          photoMetadata.faceModelVersion == currentFaceModelVersion) {
        logger.info(
          'Face embedding already completed for photo ${job.photoId} with model version $currentFaceModelVersion, skipping',
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
      await onProgress(job.id, 1.0);
      return;
    }

    await onProgress(job.id, 0.2);

    final faces = await faceDetectionProvider!.detectFaces(imageBytes);
    if (faces.isEmpty) {
      logger.info('No faces detected for face embedding');
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

    await onProgress(job.id, 0.4);

    logger.info('Detected ${faces.length} faces for embedding generation');

    final faceRecords = <FaceDetectionRecord>[];
    bool allEmbeddingsSuccessful = true;

    for (var i = 0; i < faces.length; i++) {
      final face = faces[i];
      await onProgress(job.id, 0.5 + (0.4 * i / faces.length));

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
      if (photoMetadata != null) {
        final updatedMetadata = photoMetadata.copyWith(
          faceStatus: FaceStatus.failed,
        );
        await database.photoMetadata.upsert(updatedMetadata);
      }
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

    if (photoMetadata != null) {
      final updatedMetadata = photoMetadata.copyWith(
        faceStatus: FaceStatus.completed,
      );
      await database.photoMetadata.upsert(updatedMetadata);
    }

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
    if (embeddingProvider == null) {
      throw StateError('No embedding provider available');
    }

    await onProgress(job.id, 0.1);

    final imageBytes = await photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }

    await onProgress(job.id, 0.3);

    final embedding = await embeddingProvider!.generateEmbedding(imageBytes);
    await _saveEmbedding(job.photoId, embedding);

    await onProgress(job.id, 0.5);

    final analysis = await analyzeImageQuality(imageBytes);
    await _saveImageAnalysis(job.photoId, analysis);

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
      for (var y = 0; y < decoded.height; y += decoded.height ~/ 10) {
        for (var x = 0; x < decoded.width; x += decoded.width ~/ 10) {
          final pixel = decoded.getPixel(x, y);
          final colorKey =
              '#${pixel.r.toInt().toRadixString(16).padLeft(2, '0')}${pixel.g.toInt().toRadixString(16).padLeft(2, '0')}${pixel.b.toInt().toRadixString(16).padLeft(2, '0')}';
          colorCounts[colorKey] = (colorCounts[colorKey] ?? 0) + 1;
        }
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
    List<FaceDetection> faces,
  ) async {
    final records = faces
        .asMap()
        .entries
        .map(
          (entry) => FaceDetectionRecord(
            id: '${photoId}_${entry.key}',
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
}
