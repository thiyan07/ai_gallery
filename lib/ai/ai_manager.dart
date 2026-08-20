import 'dart:typed_data';

import '../ai/ai_job_processor.dart';
import '../ai/providers/embedding_provider.dart';
import '../ai/providers/object_detection_provider.dart';
import '../ai/providers/face_detection_provider.dart';
import '../domain/models/ai_job.dart';
import '../domain/models/user_settings.dart';
import '../core/jobs/background_job_queue.dart';
import '../domain/repositories/photo_repository.dart';
import '../core/database/app_database.dart';
import '../core/logging/app_logger.dart';

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
    this.ocrProvider,
  }) : _jobQueue = jobQueue,
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
  final ObjectDetectionProvider? Function()? ocrProvider;

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
    final processor = AIJobProcessor(
      database: _database,
      photoRepository: _photoRepository,
      logger: _logger,
      embeddingProvider: _embeddingProvider(),
      faceEmbeddingProvider: _faceEmbeddingProvider?.call(),
      objectDetectionProvider: _objectDetectionProvider?.call(),
      faceDetectionProvider: _faceDetectionProvider?.call(),
      ocrProvider: ocrProvider?.call(),
    );

    await _jobQueue.updateJobStatus(
      job.id,
      status: AIJobStatus.running,
      startedAt: DateTime.now(),
    );

    try {
      await processor.processJob(job, (jobId, progress) async {
        await _jobQueue.updateJobStatus(jobId, progress: progress);
      });

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
}
