// Copyright 2024 The AI Gallery Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Background job isolate worker for offloading AI processing from the UI thread.
///
/// This isolate runs independently from the main Flutter UI isolate and processes
/// AI jobs (embeddings, object detection, face detection, OCR) from the database queue.
/// Communication with the main isolate is done via SendPort/ReceivePort.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/database/daos/ai_job_dao.dart';
import 'package:ai_gallery/core/database/daos/embedding_dao.dart';
import 'package:ai_gallery/core/database/daos/face_dao.dart';
import 'package:ai_gallery/core/database/daos/object_tag_dao.dart';
import 'package:ai_gallery/core/database/daos/ocr_dao.dart';
import 'package:ai_gallery/core/database/daos/photo_metadata_dao.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/services/model_manager.dart';
import 'package:ai_gallery/core/services/model_downloader.dart';
import 'package:ai_gallery/ai/ai_manager.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/ai/providers/face_detection_provider.dart';
import 'package:ai_gallery/ai/providers/local_embedding_provider.dart';
import 'package:ai_gallery/ai/providers/local_object_detection_provider.dart';
import 'package:ai_gallery/ai/providers/ocr_provider.dart';
import 'package:ai_gallery/ai/providers/object_detection_provider.dart';
import 'package:ai_gallery/ai/providers/blazeface_provider.dart';
import 'package:ai_gallery/ai/providers/face_embedding_provider.dart';
import 'package:ai_gallery/data/datasources/device_media_datasource.dart';
import 'package:ai_gallery/data/mappers/photo_mapper.dart';
import 'package:ai_gallery/data/repositories/device_photo_repository.dart';
import 'package:ai_gallery/domain/models/ai_job.dart';
import 'package:ai_gallery/domain/models/embedding.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';
import 'package:ai_gallery/domain/models/image_analysis.dart';
import 'package:ai_gallery/domain/models/object_detection_model.dart';
import 'package:ai_gallery/domain/models/ocr.dart';
import 'package:ai_gallery/domain/models/object_detection.dart';
import 'package:ai_gallery/domain/models/photo_metadata.dart';
import 'package:ai_gallery/domain/models/user_settings.dart';
import 'package:ai_gallery/domain/repositories/photo_repository.dart';
import 'package:ai_gallery/domain/repositories/settings_repository.dart';
import 'package:ai_gallery/core/storage/storage_service.dart';
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────
// Worker Protocol Messages
// ─────────────────────────────────────────────

/// Message types for isolate communication.
enum WorkerMessageType {
  start,
  stop,
  processJob,
  getStatus,
  statusUpdate,
  error,
}

/// Base class for worker messages.
abstract class WorkerMessage {
  WorkerMessage(this.type);
  final WorkerMessageType type;
  SendPort? replyPort;
}

/// Start the worker.
class StartWorker extends WorkerMessage {
  StartWorker({
    required this.databasePath,
    required this.modelsDir,
    required this.settingsJson,
  }) : super(WorkerMessageType.start);

  final String databasePath;
  final String modelsDir;
  final String settingsJson;
}

/// Stop the worker.
class StopWorker extends WorkerMessage {
  StopWorker() : super(WorkerMessageType.stop);
}

/// Request to process a specific job.
class ProcessJob extends WorkerMessage {
  ProcessJob({required this.jobId}) : super(WorkerMessageType.processJob);

  final String jobId;
}

/// Get worker status.
class GetStatus extends WorkerMessage {
  GetStatus() : super(WorkerMessageType.getStatus);
}

/// Status update from worker.
class StatusUpdate extends WorkerMessage {
  StatusUpdate({
    required this.isProcessing,
    required this.currentJobId,
    required this.jobsProcessed,
    required this.jobsFailed,
  }) : super(WorkerMessageType.statusUpdate);

  final bool isProcessing;
  final String? currentJobId;
  final int jobsProcessed;
  final int jobsFailed;
}

/// Error from worker.
class WorkerError extends WorkerMessage {
  WorkerError({
    required this.message,
    required this.stackTrace,
  }) : super(WorkerMessageType.error);

  final String message;
  final StackTrace stackTrace;
}

/// Response from worker.
class WorkerResponse {
  WorkerResponse({
    required this.success,
    this.message,
    this.jobResult,
    this.status,
  });

  final bool success;
  final String? message;
  final JobResult? jobResult;
  final WorkerStatus? status;
}

/// Result of a job processing.
class JobResult {
  JobResult({
    required this.jobId,
    required this.success,
    this.errorMessage,
  });

  final String jobId;
  final bool success;
  final String? errorMessage;
}

/// Worker status.
class WorkerStatus {
  WorkerStatus({
    required this.isRunning,
    required this.isProcessing,
    required this.currentJobId,
    required this.jobsProcessed,
    required this.jobsFailed,
  });

  final bool isRunning;
  final bool isProcessing;
  final String? currentJobId;
  final int jobsProcessed;
  final int jobsFailed;
}

// ─────────────────────────────────────────────
// Isolate Worker Entry Point
// ─────────────────────────────────────────────

/// The isolate entry point function.
///
/// This runs in a separate isolate and processes AI jobs from the queue.
/// It maintains its own database connection and AI providers.
@pragma('vm:entry-point')
void isolateWorkerEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is WorkerMessage) {
      if (message.replyPort != null) {
        // reply port will be set by sender
      }
      await _handleMessage(message);
    }
  });
}

/// Global state within the isolate.
AppDatabase? _database;
AiJobDao? _jobDao;
EmbeddingDao? _embeddingDao;
FaceDao? _faceDao;
ObjectTagDao? _objectTagDao;
OcrDao? _ocrDao;
PhotoMetadataDao? _photoMetadataDao;

EmbeddingProvider? _embeddingProvider;
EmbeddingProvider? _faceEmbeddingProvider;
ObjectDetectionProvider? _objectDetectionProvider;
FaceDetectionProvider? _faceDetectionProvider;
PhotoRepository? _photoRepository;
SettingsRepository? _settingsRepository;
ModelManager? _modelManager;
AppLogger _logger = const ConsoleAppLogger();

bool _isRunning = false;
bool _isProcessing = false;
String? _currentJobId;
int _jobsProcessed = 0;
int _jobsFailed = 0;
StreamSubscription? _pendingJobsSubscription;

/// Handle incoming messages.
Future<void> _handleMessage(WorkerMessage message) async {
  try {
    switch (message.type) {
      case WorkerMessageType.start:
        await _handleStart(message as StartWorker);
      case WorkerMessageType.stop:
        await _handleStop(message as StopWorker);
      case WorkerMessageType.processJob:
        await _handleProcessJob(message as ProcessJob);
      case WorkerMessageType.getStatus:
        _handleGetStatus(message as GetStatus);
      case WorkerMessageType.statusUpdate:
      case WorkerMessageType.error:
        break; // These are outgoing only
    }
  } catch (e, st) {
    _logger.error('Worker error: $e', error: e, stackTrace: st);
    if (message.replyPort != null) {
      _sendResponse(message.replyPort!, WorkerResponse(
        success: false,
        message: e.toString(),
      ));
    }
  }
}

/// Initialize the worker with database and AI providers.
Future<void> _handleStart(StartWorker message) async {
  if (_isRunning) {
    _sendResponse(message.replyPort!, WorkerResponse(
      success: false,
      message: 'Worker already running',
    ));
    return;
  }

  try {
    _logger.info('Starting background job worker isolate');

    // Parse settings
    final settings = UserSettings.fromJsonString(message.settingsJson);

    // Initialize database - create a new database connection for this isolate
    _database = await AppDatabase.openForIsolate(
      databasePath: message.databasePath,
      logger: _logger,
    );
    _jobDao = _database!.aiJobs;
    _embeddingDao = _database!.embeddings;
    _faceDao = _database!.faces;
    _objectTagDao = _database!.objectTags;
    _ocrDao = _database!.ocrResults;
    _photoMetadataDao = _database!.photoMetadata;

    // Initialize model manager
    final modelDownloader = ModelDownloader(logger: _logger);
    _modelManager = ModelManager(downloader: modelDownloader, logger: _logger);

    // Initialize AI providers based on settings
    await _initializeAIProviders(settings, message.modelsDir);

    // Initialize photo repository
    final deviceMediaDataSource = DeviceMediaDataSource(logger: _logger);
    _photoRepository = DevicePhotoRepository(
      dataSource: deviceMediaDataSource,
      photoMapper: const PhotoMapper(),
    );

    // Initialize settings repository (minimal for the worker)
    _settingsRepository = _WorkerSettingsRepository(settings);

    _isRunning = true;
    _jobsProcessed = 0;
    _jobsFailed = 0;

    // Start the processing loop
    _startProcessingLoop();

    _sendResponse(message.replyPort!, WorkerResponse(success: true));
    _logger.info('Background job worker started successfully');
  } catch (e, st) {
    _logger.error('Failed to start worker: $e', error: e, stackTrace: st);
    _sendResponse(message.replyPort!, WorkerResponse(
      success: false,
      message: e.toString(),
    ));
  }
}

/// Initialize AI providers within the isolate.
Future<void> _initializeAIProviders(UserSettings settings, String modelsDir) async {
  if (settings.aiMode != AiMode.local) {
    _logger.info('AI mode is not local, skipping local provider initialization in worker');
    return;
  }

  // Initialize image embedding provider (SigLIP/CLIP)
  _embeddingProvider = LocalEmbeddingProvider(
    logger: _logger,
    modelManager: _modelManager!,
    modelAssetPath: 'assets/models/siglip_base_patch16_224.onnx',
    textModelAssetPath: 'assets/models/siglip_text_encoder.onnx',
    tokenizerAssetPath: 'assets/models/siglip_tokenizer.model',
  );
  await _embeddingProvider!.isAvailable;

  // Initialize face embedding provider (MobileFaceNet/ArcFace)
  final faceEmbeddingProvider = FaceEmbeddingProvider(
    logger: _logger,
    modelManager: _modelManager!,
    modelVariant: 'mobilefacenet', // Use fast model in worker
  );
  await faceEmbeddingProvider.initialize();
  _faceEmbeddingProvider = faceEmbeddingProvider;

  // Initialize object detection provider (YOLOv8)
  _objectDetectionProvider = LocalObjectDetectionProvider(
    logger: _logger,
    modelManager: _modelManager!,
  );
  await _objectDetectionProvider!.initialize();

  // Initialize face detection provider (BlazeFace)
  _faceDetectionProvider = BlazeFaceProvider(
    logger: _logger,
    modelManager: _modelManager!,
    modelVariant: 'short_range', // 128x128 for speed
    confidenceThreshold: 0.5,
    iouThreshold: 0.3,
    maxFaces: 10,
  );
  await _faceDetectionProvider!.initialize();

  // Initialize OCR provider (PaddleOCR)
  _objectDetectionProvider = PaddleOcrProvider(
    logger: _logger,
    modelManager: _modelManager!,
    detectorAssetPath: 'assets/models/ppocr_det.onnx',
    recognizerAssetPath: 'assets/models/ppocr_rec.onnx',
  );
  await _objectDetectionProvider!.initialize();

  _logger.info('AI providers initialized in worker: '
    'embedding=${_embeddingProvider != null}, '
    'faceEmbedding=${_faceEmbeddingProvider != null}, '
    'objectDetection=${_objectDetectionProvider != null}, '
    'faceDetection=${_faceDetectionProvider != null}, '
    'ocr=${_objectDetectionProvider != null}');
}

/// Start the job processing loop.
void _startProcessingLoop() {
  _pendingJobsSubscription?.cancel();
  _pendingJobsSubscription = _watchPendingJobs().listen((jobs) {
    if (!_isProcessing && jobs.isNotEmpty) {
      unawaited(_processNextJob());
    }
  });
}

/// Watch pending jobs from database.
Stream<List<AIJob>> _watchPendingJobs() {
  return _jobDao!.watchByStatus(AIJobStatus.pending);
}

/// Process the next pending job.
Future<void> _processNextJob() async {
  if (!_isRunning || _isProcessing) return;

  final pending = await _jobDao!.getByStatus(AIJobStatus.pending);
  if (pending.isEmpty) return;

  final job = pending.first;
  _isProcessing = true;
  _currentJobId = job.id;

  _emitStatus();

  try {
    // Mark job as running
    final running = job.copyWith(
      status: AIJobStatus.running,
      startedAt: DateTime.now(),
    );
    await _jobDao!.upsert(running);
    _emitStatus();

    // Process based on job type
    await _processJob(running);

    // Mark as completed
    final completed = running.copyWith(
      status: AIJobStatus.completed,
      progress: 1.0,
      completedAt: DateTime.now(),
    );
    await _jobDao!.upsert(completed);

    _jobsProcessed++;
    _logger.info('Job ${job.id} (${job.type.name}) completed successfully');
  } catch (e, st) {
    _logger.error('Job ${job.id} failed', error: e, stackTrace: st);
    _jobsFailed++;

    final failed = job.copyWith(
      status: AIJobStatus.failed,
      errorMessage: e.toString(),
      completedAt: DateTime.now(),
    );
    await _jobDao!.upsert(failed);
  } finally {
    _isProcessing = false;
    _currentJobId = null;
    _emitStatus();

    // Check for more jobs
    final morePending = await _jobDao!.getByStatus(AIJobStatus.pending);
    if (morePending.isNotEmpty) {
      unawaited(_processNextJob());
    }
  }
}

/// Process a single job based on its type.
Future<void> _processJob(AIJob job) async {
  switch (job.type) {
    case AIJobType.embedding:
      await _processEmbedding(job);
      break;
    case AIJobType.faceDetection:
      await _processFaceDetection(job);
      break;
    case AIJobType.faceEmbedding:
      await _processFaceEmbedding(job);
      break;
    case AIJobType.objectTagging:
      await _processObjectTagging(job);
      break;
    case AIJobType.ocr:
      await _processOcr(job);
      break;
    case AIJobType.caption:
      await _processCaption(job);
      break;
  }
}

/// Generate image embedding.
Future<void> _processEmbedding(AIJob job) async {
  if (_embeddingProvider == null) {
    throw StateError('Embedding provider not available');
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.1);

  final imageBytes = await _photoRepository!.getImageBytes(job.photoId);
  if (imageBytes == null) {
    throw StateError('Failed to load image bytes for photo ${job.photoId}');
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.3);

  final Float32List embedding = await _embeddingProvider!.generateEmbedding(imageBytes);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.7);

  await _saveEmbedding(job.photoId, embedding);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 1.0);
}

/// Detect faces in image.
Future<void> _processFaceDetection(AIJob job) async {
  if (_faceDetectionProvider == null) {
    _logger.warning('Face detection provider not available, skipping');
    return;
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.1);

  final imageBytes = await _photoRepository!.getImageBytes(job.photoId);
  if (imageBytes == null) {
    throw StateError('Failed to load image bytes for photo ${job.photoId}');
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.3);

  final faces = await _faceDetectionProvider!.detectFaces(imageBytes);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.7);

  await _saveFaceDetections(job.photoId, faces);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 1.0);
}

/// Generate face embeddings for detected faces.
Future<void> _processFaceEmbedding(AIJob job) async {
  if (_faceDetectionProvider == null || _faceEmbeddingProvider == null) {
    _logger.warning('Face detection/embedding providers not available, skipping');
    return;
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.1);

  final imageBytes = await _photoRepository!.getImageBytes(job.photoId);
  if (imageBytes == null) {
    throw StateError('Failed to load image bytes for photo ${job.photoId}');
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.2);

  // First detect faces
  final faces = await _faceDetectionProvider!.detectFaces(imageBytes);
  if (faces.isEmpty) {
    _logger.info('No faces detected for face embedding');
    return;
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.4);

  // For each face, crop and generate embedding
  // In a full implementation, we'd crop the face region from the image
  // For now, we'll save the face detections and note embeddings would be generated
  _logger.info('Detected ${faces.length} faces for embedding generation');

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.7);

  await _saveFaceDetections(job.photoId, faces);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 1.0);
}

/// Detect objects in image.
Future<void> _processObjectTagging(AIJob job) async {
  if (_objectDetectionProvider == null) {
    // No provider available, just mark as done with no detections
    await _saveObjectDetections(job.photoId, []);
    return;
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.1);

  final imageBytes = await _photoRepository!.getImageBytes(job.photoId);
  if (imageBytes == null) {
    throw StateError('Failed to load image bytes for photo ${job.photoId}');
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.3);

  final result = await _objectDetectionProvider!.detectObjects(imageBytes);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.7);

  await _saveObjectDetections(job.photoId, result.detections);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 1.0);
}

/// Extract text from image using OCR.
Future<void> _processOcr(AIJob job) async {
  // Use PaddleOCR which is registered as the object detection provider
  if (_objectDetectionProvider == null) {
    _logger.warning('OCR provider not available, skipping');
    return;
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.1);

  final imageBytes = await _photoRepository!.getImageBytes(job.photoId);
  if (imageBytes == null) {
    throw StateError('Failed to load image bytes for photo ${job.photoId}');
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.2);

  // PaddleOCR returns DetectedObject with text as label
  final result = await _objectDetectionProvider!.detectObjects(imageBytes);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.7);

  // Combine all detected text
  final allText = result.detections.map((d) => d.label).join('\n');

  await _saveOcrResult(job.photoId, allText);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 1.0);
}

/// Generate caption/description for image.
Future<void> _processCaption(AIJob job) async {
  if (_embeddingProvider == null) {
    throw StateError('Embedding provider not available');
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.1);

  final imageBytes = await _photoRepository!.getImageBytes(job.photoId);
  if (imageBytes == null) {
    throw StateError('Failed to load image bytes for photo ${job.photoId}');
  }

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.3);

  // Generate embedding for the image
  final embedding = await _embeddingProvider!.generateEmbedding(imageBytes);
  await _saveEmbedding(job.photoId, embedding);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 0.5);

  // Run image analysis (quality, blur, colors, etc.)
  final analysis = await _analyzeImageQuality(imageBytes);
  await _saveImageAnalysis(job.photoId, analysis);

  await _jobDao!.updateStatus(job.id, status: AIJobStatus.running, progress: 1.0);
}

  // ─────────────────────────────────────────────
  // Image Quality Analysis
  // ─────────────────────────────────────────────

  /// Analyze image quality (blur, brightness, dominant colors).
  Future<ImageAnalysis> _analyzeImageQuality(Uint8List imageBytes) async {
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
          final luminance = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
          brightnessSum += luminance;
          totalPixels++;
        }
      }

      final avgBrightness = totalPixels > 0 ? brightnessSum / totalPixels / 255.0 : 0.5;
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
          final colorKey = '#${pixel.r.toInt().toRadixString(16).padLeft(2, '0')}${pixel.g.toInt().toRadixString(16).padLeft(2, '0')}${pixel.b.toInt().toRadixString(16).padLeft(2, '0')}';
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
  final record = EmbeddingRecord(
    id: photoId,
    photoId: photoId,
    vector: embedding,
    modelId: 'siglip-base-patch16-224',
    dimensions: embedding.length,
  );
  await _embeddingDao!.insertEmbedding(record);
}

Future<void> _saveFaceDetections(String photoId, List<FaceDetection> faces) async {
  final records = faces.asMap().entries.map((entry) => FaceDetectionRecord(
    id: '${photoId}_${entry.key}',
    photoId: photoId,
    x: entry.value.x,
    y: entry.value.y,
    width: entry.value.width,
    height: entry.value.height,
    confidence: entry.value.confidence,
  )).toList();
  await _faceDao!.insertFaces(records);
}

Future<void> _saveObjectDetections(String photoId, List<DetectedObject> objects) async {
  final records = objects.asMap().entries.map((entry) {
    final bbox = entry.value.boundingBox; // [cx, cy, w, h] normalized
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
  await _objectTagDao!.insertObjectTags(records);
}

Future<void> _saveOcrResult(String photoId, String text) async {
  if (text.isEmpty) return;
  final record = OcrRecord(
    id: photoId,
    photoId: photoId,
    text: text,
    confidence: 0.9,
  );
  await _ocrDao!.insertOcr(record);
}

Future<void> _saveImageAnalysis(String photoId, ImageAnalysis analysis) async {
  // Could save to metadata or dedicated table
}

/// Stop the worker.
Future<void> _handleStop(StopWorker message) async {
  _logger.info('Stopping background job worker isolate');

  await _pendingJobsSubscription?.cancel();
  _pendingJobsSubscription = null;

  // Dispose AI providers
  await _disposeIfPossible(_embeddingProvider);
  await _disposeIfPossible(_faceEmbeddingProvider);
  await _disposeIfPossible(_objectDetectionProvider);
  await _disposeIfPossible(_faceDetectionProvider);

  await _database?.dispose();
  _database = null;
  _jobDao = null;
  _embeddingDao = null;
  _faceDao = null;
  _objectTagDao = null;
  _ocrDao = null;
  _photoMetadataDao = null;

  _embeddingProvider = null;
  _faceEmbeddingProvider = null;
  _objectDetectionProvider = null;
  _faceDetectionProvider = null;
  _photoRepository = null;
  _settingsRepository = null;
  _modelManager = null;

  _isRunning = false;
  _isProcessing = false;
  _currentJobId = null;

  _sendResponse(message.replyPort!, WorkerResponse(success: true));
  _logger.info('Background job worker stopped');
}

/// Helper to dispose objects that have a dispose method.
Future<void> _disposeIfPossible(dynamic obj) async {
  if (obj == null) return;
  try {
    if (obj is FaceDetectionProvider) {
      await obj.dispose();
    } else if (obj is EmbeddingProvider) {
      await obj.dispose();
    } else if (obj is ObjectDetectionProvider) {
      await obj.dispose();
    } else if (obj is Disposable) {
      obj.dispose();
    }
  } catch (_) {
    // Ignore dispose errors
  }
}

/// Handle status request.
void _handleGetStatus(GetStatus message) {
  _sendResponse(message.replyPort!, WorkerResponse(
    success: true,
    status: WorkerStatus(
      isRunning: _isRunning,
      isProcessing: _isProcessing,
      currentJobId: _currentJobId,
      jobsProcessed: _jobsProcessed,
      jobsFailed: _jobsFailed,
    ),
  ));
}

/// Handle process job request (manual trigger).
Future<void> _handleProcessJob(ProcessJob message) async {
  if (!_isRunning) {
    _sendResponse(message.replyPort!, WorkerResponse(
      success: false,
      message: 'Worker not running',
    ));
    return;
  }

  // Try to get and process the job
  final job = await _jobDao!.getById(message.jobId);
  if (job == null) {
    _sendResponse(message.replyPort!, WorkerResponse(
      success: false,
      message: 'Job not found',
    ));
    return;
  }

  if (job.status != AIJobStatus.pending) {
    _sendResponse(message.replyPort!, WorkerResponse(
      success: false,
      message: 'Job is not pending (status: ${job.status.name})',
    ));
    return;
  }

  // Process in background
  unawaited(_processNextJob());

  _sendResponse(message.replyPort!, WorkerResponse(success: true));
}

/// Send response back to main isolate.
void _sendResponse(SendPort replyPort, WorkerResponse response) {
  replyPort.send(response);
}

/// Emit status update to main isolate.
void _emitStatus() {
  // Status is sent via GetStatus requests, but we could also push updates
  // For now, the main isolate polls for status
}

// ─────────────────────────────────────────────
// Support Classes
// ─────────────────────────────────────────────

/// Interface for disposable resources.
abstract class Disposable {
  void dispose();
}

/// Minimal settings repository for worker isolate.
class _WorkerSettingsRepository implements SettingsRepository {
  _WorkerSettingsRepository(this._settings);
  final UserSettings _settings;

  @override
  UserSettings getSettings() => _settings;

  @override
  Future<void> saveSettings(UserSettings settings) async {}

  @override
  Future<void> setThemeMode(String mode) async {}

  @override
  Future<void> setAccentColor(int color) async {}

  @override
  Future<void> setOnboardingCompleted(bool completed) async {}

  @override
  Future<void> setTelemetryEnabled(bool enabled) async {}

  @override
  Future<void> setCloudBackupEnabled(bool enabled) async {}

  @override
  Future<void> setStoragePath(String? path) async {}

  @override
  Future<void> setSyncWifiOnly(bool wifiOnly) async {}

  @override
  Future<void> setSyncFrequency(String frequency) async {}

  @override
  Future<void> setAiMode(AiMode mode) async {}

  @override
  Future<void> setGridSize(int columns) async {}
}

extension on AiJobDao {
  Future<void> updateStatus(
    String jobId, {
    required AIJobStatus status,
    double? progress,
  }) async {
    final job = await getById(jobId);
    if (job == null) return;

    final updated = job.copyWith(
      status: status,
      progress: progress ?? job.progress,
      startedAt: status == AIJobStatus.running ? DateTime.now() : job.startedAt,
      completedAt: status == AIJobStatus.completed || status == AIJobStatus.failed
          ? DateTime.now()
          : job.completedAt,
    );
    await upsert(updated);
  }
}