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

import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/database/daos/ai_job_dao.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/services/model_manager.dart';
import 'package:ai_gallery/core/services/model_downloader.dart';
import 'package:ai_gallery/core/utils/device_capabilities.dart';
import 'package:ai_gallery/ai/ai_job_processor.dart';
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
import 'package:ai_gallery/domain/models/user_settings.dart';

// ─────────────────────────────────────────────
// Worker Protocol Messages
// ─────────────────────────────────────────────

/// Message types for isolate communication.
enum WorkerMessageType {
  start,
  stop,
  processJob,
  cancelJob,
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

/// Request to cancel the currently running job.
class CancelJob extends WorkerMessage {
  CancelJob({required this.jobId}) : super(WorkerMessageType.cancelJob);

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
  WorkerError({required this.message, required this.stackTrace})
    : super(WorkerMessageType.error);

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
  JobResult({required this.jobId, required this.success, this.errorMessage});

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
  _mainSendPort = mainSendPort;
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is WorkerMessage) {
      await _handleMessage(message);
    }
  });
}

/// Global state within the isolate.
SendPort? _mainSendPort;
AppDatabase? _database;
AiJobDao? _jobDao;

AIJobProcessor? _processor;
ModelManager? _modelManager;
AppLogger _logger = const ConsoleAppLogger();

bool _isRunning = false;
bool _isProcessing = false;
String? _currentJobId;
bool _cancelRequested = false;
int _jobsProcessed = 0;
int _jobsFailed = 0;
StreamSubscription? _pendingJobsSubscription;

/// Maximum time a single job can run before being marked as failed.
const _jobTimeout = Duration(minutes: 15);

/// Maximum number of retries before marking a job as permanently failed.
const _maxRetries = 3;

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
      case WorkerMessageType.cancelJob:
        await _handleCancelJob(message as CancelJob);
      case WorkerMessageType.getStatus:
        _handleGetStatus(message as GetStatus);
      case WorkerMessageType.statusUpdate:
      case WorkerMessageType.error:
        break; // These are outgoing only
    }
  } catch (e, st) {
    _logger.error('Worker error: $e', error: e, stackTrace: st);
    if (message.replyPort != null) {
      _sendResponse(
        message.replyPort!,
        WorkerResponse(success: false, message: e.toString()),
      );
    }
  }
}

/// Initialize the worker with database and AI providers.
Future<void> _handleStart(StartWorker message) async {
  if (_isRunning) {
    _sendResponse(
      message.replyPort!,
      WorkerResponse(success: false, message: 'Worker already running'),
    );
    return;
  }

  try {
    _logger.info('Starting background job worker isolate');

    final settings = UserSettings.fromJsonString(message.settingsJson);

    _database = await AppDatabase.openForIsolate(
      databasePath: message.databasePath,
      logger: _logger,
    );
    _jobDao = _database!.aiJobs;

    final modelDownloader = ModelDownloader(logger: _logger);
    _modelManager = ModelManager(downloader: modelDownloader, logger: _logger);

    // Initialize AI providers
    EmbeddingProvider? embeddingProvider;
    EmbeddingProvider? faceEmbeddingProvider;
    ObjectDetectionProvider? objectDetectionProvider;
    ObjectDetectionProvider? ocrProvider;
    FaceDetectionProvider? faceDetectionProvider;

    if (settings.aiMode == AiMode.local) {
      // Embedding provider — tolerate missing models, keep worker running.
      try {
        embeddingProvider = LocalEmbeddingProvider(
          logger: _logger,
          modelManager: _modelManager!,
          modelAssetPath: 'assets/models/siglip_base_patch16_224.onnx',
          textModelAssetPath: 'assets/models/siglip_text_encoder.onnx',
          tokenizerAssetPath: 'assets/models/siglip_tokenizer.model',
        );
        await embeddingProvider.isAvailable;
      } catch (e) {
        _logger.warning('Worker embedding provider deferred: $e');
      }

      // Face embedding — tier-aware to match main isolate (fixes dimension skew).
      try {
        final caps = await DeviceCapabilities.instance;
        final isHighEnd = caps.tier.index >= DeviceTier.high.index;
        final faceVariant = isHighEnd ? 'arcface_r18' : 'mobilefacenet';
        final faceAsset = isHighEnd ? null : 'assets/models/mobilefacenet.onnx';
        final faceEmbProvider = FaceEmbeddingProvider(
          logger: _logger,
          modelManager: _modelManager!,
          modelAssetPath: faceAsset,
          modelVariant: faceVariant,
        );
        try {
          await faceEmbProvider.initialize();
        } catch (e) {
          _logger.warning('Worker face embedding deferred (model not ready): $e');
        }
        faceEmbeddingProvider = faceEmbProvider;
      } catch (e) {
        _logger.warning('Worker face embedding setup failed: $e');
      }

      try {
        final objProvider = LocalObjectDetectionProvider(
          logger: _logger,
          modelManager: _modelManager!,
          modelAssetPath: 'assets/models/yolov8n.onnx',
        );
        try {
          await objProvider.initialize();
        } catch (e) {
          _logger.warning('Worker object detection deferred: $e');
        }
        objectDetectionProvider = objProvider;
      } catch (e) {
        _logger.warning('Worker object detection setup failed: $e');
      }

      try {
        faceDetectionProvider = BlazeFaceProvider(
          logger: _logger,
          modelManager: _modelManager!,
          modelAssetPath: 'assets/models/blaze_face_short_range.onnx',
          modelVariant: 'short_range',
          confidenceThreshold: 0.5,
          iouThreshold: 0.3,
          maxFaces: 10,
        );
        try {
          await faceDetectionProvider.initialize();
        } catch (e) {
          _logger.warning('Worker face detection deferred: $e');
        }
      } catch (e) {
        _logger.warning('Worker face detection setup failed: $e');
      }

      try {
        ocrProvider = PaddleOcrProvider(
          logger: _logger,
          modelManager: _modelManager!,
          detectorAssetPath: 'assets/models/ppocr_det.onnx',
          recognizerAssetPath: 'assets/models/ppocr_rec.onnx',
        );
        try {
          await ocrProvider.initialize();
        } catch (e) {
          _logger.warning('Worker OCR deferred: $e');
        }
      } catch (e) {
        _logger.warning('Worker OCR setup failed: $e');
      }

      _logger.info('AI providers initialized in worker (available providers may be deferred)');
    }

    final deviceMediaDataSource = DeviceMediaDataSource(logger: _logger);
    final photoRepository = DevicePhotoRepository(
      dataSource: deviceMediaDataSource,
      photoMapper: const PhotoMapper(),
    );

    _processor = AIJobProcessor(
      database: _database!,
      photoRepository: photoRepository,
      logger: _logger,
      embeddingProvider: embeddingProvider,
      faceEmbeddingProvider: faceEmbeddingProvider,
      objectDetectionProvider: objectDetectionProvider,
      faceDetectionProvider: faceDetectionProvider,
      ocrProvider: ocrProvider,
    );

    _isRunning = true;
    _jobsProcessed = 0;
    _jobsFailed = 0;

    // Recover any jobs stuck in 'running' from a previous crash
    final recoveredCount = await _jobDao!.resetStuckJobs();
    if (recoveredCount > 0) {
      _logger.info('Recovered $recoveredCount stuck jobs from previous session');
    }

    _startProcessingLoop();

    _sendResponse(message.replyPort!, WorkerResponse(success: true));
    _logger.info('Background job worker started successfully');
  } catch (e, st) {
    _logger.error('Failed to start worker: $e', error: e, stackTrace: st);
    _sendResponse(
      message.replyPort!,
      WorkerResponse(success: false, message: e.toString()),
    );
  }
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
  _isProcessing = true;
  _cancelRequested = false;

  final pending = await _jobDao!.getByStatus(AIJobStatus.pending);
  if (pending.isEmpty) {
    _isProcessing = false;
    return;
  }

  final job = pending.first;
  _currentJobId = job.id;

  _emitStatus();

  try {
    final running = job.copyWith(
      status: AIJobStatus.running,
      startedAt: DateTime.now(),
    );
    await _jobDao!.upsert(running);
    _emitStatus();

    // Check for cancellation before starting
    if (_cancelRequested) {
      final cancelled = running.copyWith(
        status: AIJobStatus.cancelled,
        completedAt: DateTime.now(),
      );
      await _jobDao!.upsert(cancelled);
      return;
    }

    // Run job with timeout protection
    await _processor!.processJob(running, (jobId, progress) async {
      // Check for cancellation during progress updates
      if (_cancelRequested) {
        throw StateError('Job cancelled by user');
      }
      final current = await _jobDao!.getById(jobId);
      if (current == null) return;
      final updated = current.copyWith(progress: progress);
      await _jobDao!.upsert(updated);
    }).timeout(_jobTimeout, onTimeout: () {
      throw TimeoutException(
        'Job ${job.id} exceeded timeout of ${_jobTimeout.inMinutes} minutes',
      );
    });

    final completed = running.copyWith(
      status: AIJobStatus.completed,
      progress: 1.0,
      completedAt: DateTime.now(),
    );
    await _jobDao!.upsert(completed);

    _jobsProcessed++;
    _logger.info('Job ${job.id} (${job.type.name}) completed successfully');
  } catch (e, st) {
    // Handle cancellation separately from failure
    if (_cancelRequested || (e is StateError && e.message == 'Job cancelled by user')) {
      final cancelled = job.copyWith(
        status: AIJobStatus.cancelled,
        completedAt: DateTime.now(),
      );
      await _jobDao!.upsert(cancelled);
      _logger.info('Job ${job.id} was cancelled');
    } else {
      // MODEL_NOT_READY is not transient — don't waste retries.
      if (e.toString().contains('MODEL_NOT_READY')) {
        _logger.warning('Job ${job.id} failed due to MODEL_NOT_READY, marking failed without retry: $e');
        _jobsFailed++;
        final failed = job.copyWith(
          status: AIJobStatus.failed,
          errorMessage: e.toString(),
          completedAt: DateTime.now(),
          retryCount: job.retryCount + 1,
        );
        await _jobDao!.upsert(failed);
      } else {
        _logger.error('Job ${job.id} failed', error: e, stackTrace: st);
        _jobsFailed++;

        final failed = job.copyWith(
          status: AIJobStatus.failed,
          errorMessage: e.toString(),
          completedAt: DateTime.now(),
          retryCount: job.retryCount + 1,
        );

        // Retry with exponential backoff if under max retries
        if (failed.retryCount < _maxRetries) {
          final retryDelay = Duration(seconds: (2 * failed.retryCount).clamp(1, 30));
          _logger.info(
            'Job ${job.id} failed (attempt ${failed.retryCount}/$_maxRetries), '
            'retrying in ${retryDelay.inSeconds}s',
          );
          final retried = failed.copyWith(status: AIJobStatus.pending, completedAt: null, errorMessage: null);
          await _jobDao!.upsert(retried);

        // Schedule retry after delay
        Future.delayed(retryDelay, () {
          if (_isRunning) {
            unawaited(_processNextJob());
          }
        });
      } else {
        _logger.error(
          'Job ${job.id} permanently failed after $_maxRetries attempts: $e',
          error: e,
          stackTrace: st,
        );
        await _jobDao!.upsert(failed);
      }
      }
    }
  } finally {
    _isProcessing = false;
    _currentJobId = null;
    _emitStatus();

    final morePending = await _jobDao!.getByStatus(AIJobStatus.pending);
    if (morePending.isNotEmpty) {
      unawaited(_processNextJob());
    }
  }
}

/// Stop the worker.
Future<void> _handleStop(StopWorker message) async {
  _logger.info('Stopping background job worker isolate');

  _isRunning = false;

  await _pendingJobsSubscription?.cancel();
  _pendingJobsSubscription = null;

  // Wait for any in-progress job to finish before nulling resources
  while (_isProcessing) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  await _database?.dispose();
  _database = null;
  _jobDao = null;
  _processor = null;
  _modelManager = null;
  _mainSendPort = null;

  _currentJobId = null;

  _sendResponse(message.replyPort!, WorkerResponse(success: true));
  _logger.info('Background job worker stopped');
}

/// Handle status request.
void _handleGetStatus(GetStatus message) {
  _sendResponse(
    message.replyPort!,
    WorkerResponse(
      success: true,
      status: WorkerStatus(
        isRunning: _isRunning,
        isProcessing: _isProcessing,
        currentJobId: _currentJobId,
        jobsProcessed: _jobsProcessed,
        jobsFailed: _jobsFailed,
      ),
    ),
  );
}

/// Handle process job request (manual trigger).
Future<void> _handleProcessJob(ProcessJob message) async {
  if (!_isRunning) {
    _sendResponse(
      message.replyPort!,
      WorkerResponse(success: false, message: 'Worker not running'),
    );
    return;
  }

  final job = await _jobDao!.getById(message.jobId);
  if (job == null) {
    _sendResponse(
      message.replyPort!,
      WorkerResponse(success: false, message: 'Job not found'),
    );
    return;
  }

  if (job.status != AIJobStatus.pending) {
    _sendResponse(
      message.replyPort!,
      WorkerResponse(
        success: false,
        message: 'Job is not pending (status: ${job.status.name})',
      ),
    );
    return;
  }

  unawaited(_processNextJob());

  _sendResponse(message.replyPort!, WorkerResponse(success: true));
}

/// Handle cancel job request — marks the running job as cancelled.
Future<void> _handleCancelJob(CancelJob message) async {
  if (!_isRunning) {
    _sendResponse(
      message.replyPort!,
      WorkerResponse(success: false, message: 'Worker not running'),
    );
    return;
  }

  final job = await _jobDao!.getById(message.jobId);
  if (job == null) {
    _sendResponse(
      message.replyPort!,
      WorkerResponse(success: false, message: 'Job not found'),
    );
    return;
  }

  if (job.status == AIJobStatus.running && job.id == _currentJobId) {
    // Request cancellation of the currently running job
    _cancelRequested = true;
    _logger.info('Cancellation requested for running job ${job.id}');
    _sendResponse(message.replyPort!, WorkerResponse(success: true));
  } else if (job.status == AIJobStatus.pending) {
    // Mark pending job as cancelled directly
    final cancelled = job.copyWith(
      status: AIJobStatus.cancelled,
      completedAt: DateTime.now(),
    );
    await _jobDao!.upsert(cancelled);
    _sendResponse(message.replyPort!, WorkerResponse(success: true));
  } else {
    _sendResponse(
      message.replyPort!,
      WorkerResponse(
        success: false,
        message: 'Job cannot be cancelled (status: ${job.status.name})',
      ),
    );
  }
}

/// Send response back to main isolate.
void _sendResponse(SendPort replyPort, WorkerResponse response) {
  replyPort.send(response);
}

/// Emit status update to main isolate.
void _emitStatus() {
  final port = _mainSendPort;
  if (port == null) return;
  final status = StatusUpdate(
    isProcessing: _isProcessing,
    currentJobId: _currentJobId,
    jobsProcessed: _jobsProcessed,
    jobsFailed: _jobsFailed,
  );
  try {
    port.send(status);
  } catch (e) {
    _logger.debug('Could not send status update (isolate may be shutting down): $e');
  }
}

// ─────────────────────────────────────────────
// Support Classes
// ─────────────────────────────────────────────

/// Interface for disposable resources.
abstract class Disposable {
  void dispose();
}

