import 'dart:typed_data';

import '../ai/providers/embedding_provider.dart';
import '../ai/providers/object_detection_provider.dart';
import '../ai/providers/face_detection_provider.dart';
import '../domain/models/ai_job.dart';
import '../domain/models/user_settings.dart';
import '../domain/models/face_detection.dart';
import '../domain/models/object_detection.dart';
import '../domain/models/object_detection_model.dart';
import '../domain/models/ocr.dart';
import '../domain/models/embedding.dart';
import '../domain/models/image_analysis.dart';
import '../core/jobs/background_job_queue.dart';
import '../domain/repositories/photo_repository.dart';
import '../core/database/app_database.dart';
import '../core/logging/app_logger.dart';
import '../features/people/services/face_clustering_service.dart';

/// Abstraction for coordinating AI operations across local and cloud backends.
abstract class AIManager {
  /// Whether cloud AI is available given current settings and API keys.
  bool get isCloudAvailable;

  /// Enqueues an AI job for background processing.
  Future<void> enqueue(AIJob job);

  /// Watches status updates for a specific job.
  Stream<AIJob> watchJob(String jobId);

  /// Returns all pending jobs.
  Future<List<AIJob>> getPendingJobs();

  /// Cancels a pending job.
  Future<void> cancel(String jobId);

  /// Processes an AI job (called by background queue).
  Future<void> processJob(AIJob job);
}

/// Default implementation that uses the background job queue and local providers.
class AIManagerImpl implements AIManager {
  AIManagerImpl({
    required BackgroundJobQueue jobQueue,
    required UserSettings Function() settingsProvider,
    required EmbeddingProvider? Function() embeddingProvider,
    required EmbeddingProvider? Function()? faceEmbeddingProvider,
    required ObjectDetectionProvider? Function()? objectDetectionProvider,
    required FaceDetectionProvider? Function()? faceDetectionProvider,
    required PhotoRepository photoRepository,
    required AppDatabase database,
    required AppLogger logger,
  })  : _jobQueue = jobQueue,
        _settingsProvider = settingsProvider,
        _embeddingProvider = embeddingProvider,
        _faceEmbeddingProvider = faceEmbeddingProvider,
        _objectDetectionProvider = objectDetectionProvider,
        _faceDetectionProvider = faceDetectionProvider,
        _photoRepository = photoRepository,
        _database = database,
        _logger = logger;

  final BackgroundJobQueue _jobQueue;
  final UserSettings Function() _settingsProvider;
  final EmbeddingProvider? Function() _embeddingProvider;
  final EmbeddingProvider? Function()? _faceEmbeddingProvider;
  final ObjectDetectionProvider? Function()? _objectDetectionProvider;
  final FaceDetectionProvider? Function()? _faceDetectionProvider;
  final PhotoRepository _photoRepository;
  final AppDatabase _database;
  final AppLogger _logger;

  FaceClusteringService? _faceClusteringService;

  FaceClusteringService _getFaceClusteringService() {
    _faceClusteringService ??= FaceClusteringService(
      logger: _logger,
      database: _database,
    );
    return _faceClusteringService!;
  }

  @override
  bool get isCloudAvailable {
    final settings = _settingsProvider();
    if (settings.aiMode == AiMode.local) return false;
    return settings.aiMode == AiMode.byok || settings.aiMode == AiMode.hybrid;
  }

  @override
  Future<void> enqueue(AIJob job) => _jobQueue.enqueue(job);

  @override
  Stream<AIJob> watchJob(String jobId) => _jobQueue.watchJob(jobId);

  @override
  Future<List<AIJob>> getPendingJobs() => _jobQueue.getPendingJobs();

  @override
  Future<void> cancel(String jobId) => _jobQueue.cancel(jobId);

  @override
  Future<void> processJob(AIJob job) async {
    final provider = _embeddingProvider();
    if (provider == null) {
      throw StateError('No embedding provider available');
    }

    // Update to running
    await _jobQueue.updateJobStatus(
      job.id,
      status: AIJobStatus.running,
      startedAt: DateTime.now(),
    );

    try {
      switch (job.type) {
        case AIJobType.embedding:
          await _processEmbedding(job, provider);
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
          await _processCaption(job, provider);
          break;
      }

      await _jobQueue.updateJobStatus(
        job.id,
        status: AIJobStatus.completed,
        progress: 1.0,
        completedAt: DateTime.now(),
      );
    } catch (e, st) {
      _logger.error('Job ${job.id} failed', error: e, stackTrace: st);
      await _jobQueue.updateJobStatus(
        job.id,
        status: AIJobStatus.failed,
        errorMessage: '$e\n$st',
        completedAt: DateTime.now(),
      );
      rethrow;
    }
  }

  /// Generate image embedding using the local/cloud provider.
  Future<void> _processEmbedding(AIJob job, EmbeddingProvider provider) async {
    await _jobQueue.updateJobStatus(job.id, progress: 0.1);

    final imageBytes = await _photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }

    await _jobQueue.updateJobStatus(job.id, progress: 0.3);

    final Float32List embedding = await provider.generateEmbedding(imageBytes);

    await _jobQueue.updateJobStatus(job.id, progress: 0.7);

    await _saveEmbedding(job.photoId, embedding);

    await _jobQueue.updateJobStatus(job.id, progress: 1.0);
  }

  /// Detect faces in the image.
  Future<void> _processFaceDetection(AIJob job) async {
    await _jobQueue.updateJobStatus(job.id, progress: 0.1);

    final imageBytes = await _photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }

    await _jobQueue.updateJobStatus(job.id, progress: 0.3);

    // Use the face detection provider if available
    final faceProvider = _faceDetectionProvider?.call();
    final faces = faceProvider != null
        ? await faceProvider.detectFaces(imageBytes)
        : <FaceDetection>[];

    await _jobQueue.updateJobStatus(job.id, progress: 0.7);

    await _saveFaceDetections(job.photoId, faces);

    await _jobQueue.updateJobStatus(job.id, progress: 1.0);
  }

  /// Generate face embeddings for detected faces in the image.
  Future<void> _processFaceEmbedding(AIJob job) async {
    await _jobQueue.updateJobStatus(job.id, progress: 0.1);

    final imageBytes = await _photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }

    await _jobQueue.updateJobStatus(job.id, progress: 0.2);

    // First detect faces
    final faceProvider = _faceDetectionProvider?.call();
    if (faceProvider == null) {
      _logger.warning('No face detection provider available for face embedding');
      return;
    }

    final faces = await faceProvider.detectFaces(imageBytes);
    if (faces.isEmpty) {
      _logger.info('No faces detected for face embedding');
      // Still save empty face detections
      await _saveFaceDetections(job.photoId, faces);
      await _jobQueue.updateJobStatus(job.id, progress: 1.0);
      return;
    }

    await _jobQueue.updateJobStatus(job.id, progress: 0.4);

    // Get face embedding provider
    final faceEmbeddingProvider = _faceEmbeddingProvider?.call();
    if (faceEmbeddingProvider == null) {
      _logger.warning('No face embedding provider available');
      // Save face detections without embeddings
      await _saveFaceDetections(job.photoId, faces);
      await _jobQueue.updateJobStatus(job.id, progress: 1.0);
      return;
    }

    // For each face, crop the face region and generate embedding with alignment
    _logger.info('Detected ${faces.length} faces for embedding generation');

    await _jobQueue.updateJobStatus(job.id, progress: 0.5);

    final faceRecords = <FaceDetectionRecord>[];
    for (var i = 0; i < faces.length; i++) {
      final face = faces[i];
      await _jobQueue.updateJobStatus(job.id, progress: 0.5 + (0.4 * i / faces.length));

      try {
        // Generate aligned face embedding using the embedding provider
        final embedding = await faceEmbeddingProvider.generateEmbeddingFromFace(
          imageBytes: imageBytes,
          faceDetection: face,
        );

        // Create record with embedding
        faceRecords.add(FaceDetectionRecord(
          id: '${job.photoId}_$i',
          photoId: job.photoId,
          x: face.x,
          y: face.y,
          width: face.width,
          height: face.height,
          confidence: face.confidence,
          label: null, // Will be assigned by clustering later
          embedding: embedding,
        ));
      } catch (e, st) {
        _logger.error('Failed to generate embedding for face $i', error: e, stackTrace: st);
        // Add record without embedding
        faceRecords.add(FaceDetectionRecord(
          id: '${job.photoId}_$i',
          photoId: job.photoId,
          x: face.x,
          y: face.y,
          width: face.width,
          height: face.height,
          confidence: face.confidence,
        ));
      }
    }

    await _jobQueue.updateJobStatus(job.id, progress: 0.9);

    // Save face detections with embeddings
    await _database.faces.insertFaces(faceRecords);

    // Auto-cluster faces with embeddings
    final clusteringService = _getFaceClusteringService();
    for (final faceRecord in faceRecords) {
      if (faceRecord.embedding != null) {
        try {
          await clusteringService.clusterFace(faceRecord);
        } catch (e, st) {
          _logger.error('Failed to auto-cluster face ${faceRecord.id}', error: e, stackTrace: st);
        }
      }
    }

    await _jobQueue.updateJobStatus(job.id, progress: 1.0);
  }

  /// Detect and tag objects in the image.
  Future<void> _processObjectTagging(AIJob job) async {
    await _jobQueue.updateJobStatus(job.id, progress: 0.1);

    final imageBytes = await _photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }

    await _jobQueue.updateJobStatus(job.id, progress: 0.3);

    // Use the object detection provider if available
    final objProvider = _objectDetectionProvider?.call();
    final objects = objProvider != null
        ? (await objProvider.detectObjects(imageBytes)).detections
        : <DetectedObject>[];

    await _jobQueue.updateJobStatus(job.id, progress: 0.7);

    await _saveObjectDetections(job.photoId, objects);

    await _jobQueue.updateJobStatus(job.id, progress: 1.0);
  }

  /// Extract text from image using OCR.
  Future<void> _processOcr(AIJob job) async {
    await _jobQueue.updateJobStatus(job.id, progress: 0.1);

    final imageBytes = await _photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }

    await _jobQueue.updateJobStatus(job.id, progress: 0.2);

    // Use the OCR provider (PaddleOCR or Google Vision)
    final ocrProvider = _objectDetectionProvider?.call(); // Using object detection provider which now includes PaddleOCR
    if (ocrProvider == null) {
      _logger.warning('No OCR provider available');
      return;
    }

    // PaddleOCR returns DetectedObject with text as label
    final result = await ocrProvider.detectObjects(imageBytes);

    await _jobQueue.updateJobStatus(job.id, progress: 0.7);

    // Combine all detected text
    final allText = result.detections.map((d) => d.label).join('\n');

    await _saveOcrResult(job.photoId, allText);

    await _jobQueue.updateJobStatus(job.id, progress: 1.0);
  }

  /// Generate caption/description for image.
  Future<void> _processCaption(AIJob job, EmbeddingProvider provider) async {
    await _jobQueue.updateJobStatus(job.id, progress: 0.1);

    final imageBytes = await _photoRepository.getImageBytes(job.photoId);
    if (imageBytes == null) {
      throw StateError('Failed to load image bytes for photo ${job.photoId}');
    }

    await _jobQueue.updateJobStatus(job.id, progress: 0.3);

    // Generate embedding for the image
    final embedding = await provider.generateEmbedding(imageBytes);
    await _saveEmbedding(job.photoId, embedding);

    await _jobQueue.updateJobStatus(job.id, progress: 0.5);

    // Run image analysis (quality, blur, colors, etc.)
    final analysis = await _analyzeImageQuality(imageBytes);
    await _saveImageAnalysis(job.photoId, analysis);

    await _jobQueue.updateJobStatus(job.id, progress: 1.0);
  }

  // Database persistence helpers

  Future<void> _saveEmbedding(String photoId, Float32List embedding) async {
    final record = EmbeddingRecord(
      id: photoId,
      photoId: photoId,
      vector: embedding,
      modelId: 'siglip-base-patch16-224',
      dimensions: embedding.length,
    );
    await _database.embeddings.insertEmbedding(record);
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
      label: entry.value.label,
      embedding: entry.value.embedding,
    )).toList();
    await _database.faces.insertFaces(records);
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
    await _database.objectTags.insertObjectTags(records);
  }

  Future<void> _saveOcrResult(String photoId, String text) async {
    if (text.isEmpty) return;
    final record = OcrRecord(
      id: photoId,
      photoId: photoId,
      text: text,
      confidence: 0.9, // Placeholder
    );
    await _database.ocrResults.insertOcr(record);
  }

  Future<void> _saveImageAnalysis(String photoId, ImageAnalysis analysis) async {
    // Could save to a dedicated table or update photo_metadata
  }

  // AI processing implementations (placeholders for ONNX models)

  Future<List<FaceDetection>> _detectFaces(Uint8List imageBytes) async {
    // TODO: Integrate BlazeFace/YuNet ONNX model
    return <FaceDetection>[];
  }

  Future<String> _extractText(Uint8List imageBytes) async {
    // TODO: Integrate PaddleOCR/Tesseract ONNX model
    return '';
  }

  Future<ImageAnalysis> _analyzeImageQuality(Uint8List imageBytes) async {
    // Use existing quality analysis from MetadataExtractor
    return ImageAnalysis();
  }
}