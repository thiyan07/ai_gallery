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
      embeddingProvider = LocalEmbeddingProvider(
        logger: _logger,
        modelManager: _modelManager!,
        modelAssetPath: null,
        textModelAssetPath: null,
        tokenizerAssetPath: null,
      );
      await embeddingProvider.isAvailable;

      final faceEmbProvider = FaceEmbeddingProvider(
        logger: _logger,
        modelManager: _modelManager!,
        modelVariant: 'mobilefacenet',
      );
      await faceEmbProvider.initialize();
      faceEmbeddingProvider = faceEmbProvider;

      final objProvider = LocalObjectDetectionProvider(
        logger: _logger,
        modelManager: _modelManager!,
      );
      await objProvider.initialize();
      objectDetectionProvider = objProvider;

      faceDetectionProvider = BlazeFaceProvider(
        logger: _logger,
        modelManager: _modelManager!,
        modelVariant: 'short_range',
        confidenceThreshold: 0.5,
        iouThreshold: 0.3,
        maxFaces: 10,
      );
      await faceDetectionProvider.initialize();

      ocrProvider = PaddleOcrProvider(
        logger: _logger,
        modelManager: _modelManager!,
        detectorAssetPath: 'assets/models/ppocr_det.onnx',
        recognizerAssetPath: 'assets/models/ppocr_rec.onnx',
      );
      await ocrProvider.initialize();

      _logger.info('AI providers initialized in worker');
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

    await _processor!.processJob(running, (jobId, progress) async {
      final current = await _jobDao!.getById(jobId);
      if (current == null) return;
      final updated = current.copyWith(progress: progress);
      await _jobDao!.upsert(updated);
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
  } catch (_) {
    // Main isolate may have disconnected during shutdown
  }
}

// ─────────────────────────────────────────────
// Support Classes
// ─────────────────────────────────────────────

/// Interface for disposable resources.
abstract class Disposable {
  void dispose();
}

