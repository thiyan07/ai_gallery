// Copyright 2024 The AI Gallery Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Background job queue using Dart Isolate for offloading AI processing.
///
/// This queue communicates with a worker isolate that runs in the background
/// and processes AI jobs (embeddings, object detection, etc.) from the database.
/// The UI thread enqueues jobs and receives status updates via streams.

import 'dart:async';
import 'dart:isolate';

import '../../../domain/models/ai_job.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/daos/ai_job_dao.dart';
import '../../../core/logging/app_logger.dart';
import '../jobs/background_job_worker.dart';

/// In-process background job queue using isolate worker.
class BackgroundJobQueue {
  BackgroundJobQueue({
    required AppDatabase database,
    required AppLogger logger,
    required String databasePath,
    required String modelsDir,
    required String settingsJson,
  })  : _dao = database.aiJobs,
        _logger = logger,
        _databasePath = databasePath,
        _modelsDir = modelsDir,
        _settingsJson = settingsJson;

  final AiJobDao _dao;
  final AppLogger _logger;
  final String _databasePath;
  final String _modelsDir;
  final String _settingsJson;

  SendPort? _workerSendPort;
  ReceivePort? _workerReceivePort;
  Isolate? _workerIsolate;

  final _jobControllers = <String, StreamController<AIJob>>{};
  final _statusController = StreamController<WorkerStatus>.broadcast();

  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _currentJobId;
  int _jobsProcessed = 0;
  int _jobsFailed = 0;

  /// Initializes the queue and spawns the worker isolate.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.info('Initializing background job queue with isolate worker');

    // Create receive port for worker responses
    _workerReceivePort = ReceivePort();
    _workerReceivePort!.listen(_handleWorkerMessage);

    // Spawn the worker isolate
    _workerIsolate = await Isolate.spawn(
      isolateWorkerEntryPoint,
      _workerReceivePort!.sendPort,
    );

    // Send start message to worker
    _workerSendPort = await _workerReceivePort!.first as SendPort?;

    if (_workerSendPort == null) {
      throw StateError('Failed to establish communication with worker isolate');
    }

    await _sendStartMessage();

    _isInitialized = true;
    _logger.info('Background job queue initialized with worker isolate');
  }

  /// Sends the start message to the worker.
  Future<void> _sendStartMessage() async {
    final completer = Completer<WorkerResponse>();
    final replyPort = ReceivePort();
    replyPort.listen((message) {
      if (message is WorkerResponse) {
        completer.complete(message);
        replyPort.close();
      }
    });

    final msg = StartWorker(
      databasePath: _databasePath,
      modelsDir: _modelsDir,
      settingsJson: _settingsJson,
    );
    msg.replyPort = replyPort.sendPort;

    _workerSendPort!.send(msg);

    final response = await completer.future;
    if (!response.success) {
      throw StateError('Worker failed to start: ${response.message}');
    }
  }

  /// Handles messages from the worker isolate.
  void _handleWorkerMessage(dynamic message) {
    if (message is WorkerResponse) {
      // Responses are handled via completers
      return;
    }

    if (message is SendPort) {
      // This is the worker's send port (sent on initialization)
      // Handled in initialize()
      return;
    }

    if (message is StatusUpdate) {
      _jobsProcessed = message.jobsProcessed;
      _jobsFailed = message.jobsFailed;
      _isProcessing = message.isProcessing;
      _currentJobId = message.currentJobId;
      _statusController.add(WorkerStatus(
        isRunning: true,
        isProcessing: message.isProcessing,
        currentJobId: message.currentJobId,
        jobsProcessed: message.jobsProcessed,
        jobsFailed: message.jobsFailed,
      ));
      return;
    }

    if (message is WorkerError) {
      _logger.error('Worker error: ${message.message}', stackTrace: message.stackTrace);
      return;
    }
  }

  /// Sends a message to the worker and awaits response.
  Future<WorkerResponse> _sendToWorker(WorkerMessage message) async {
    if (!_isInitialized || _workerSendPort == null) {
      throw StateError('Worker not initialized');
    }

    final completer = Completer<WorkerResponse>();
    final replyPort = ReceivePort();
    replyPort.listen((msg) {
      if (msg is WorkerResponse) {
        completer.complete(msg);
        replyPort.close();
      }
    });

    // Set reply port on the message
    message.replyPort = replyPort.sendPort;

    _workerSendPort!.send(message);
    return completer.future;
  }

  /// Enqueues a new job and notifies the worker.
  Future<void> enqueue(AIJob job) async {
    await _dao.upsert(job);
    _emit(job);
    _logger.info('Enqueued AI job ${job.id} (${job.type.name})');

    // Notify worker to process if idle
    final status = await _sendToWorker(GetStatus());
    if (status.status != null && !status.status!.isProcessing) {
      final replyPort = ReceivePort();
      try {
        final msg = ProcessJob(jobId: job.id);
        msg.replyPort = replyPort.sendPort;
        await _sendToWorker(msg);
      } finally {
        replyPort.close();
      }
    }
  }

  /// Updates job status with optional progress and error message.
  Future<void> updateJobStatus(
    String jobId, {
    AIJobStatus? status,
    double? progress,
    DateTime? startedAt,
    DateTime? completedAt,
    String? errorMessage,
  }) async {
    final job = await _dao.getById(jobId);
    if (job == null) return;

    final updated = job.copyWith(
      status: status,
      progress: progress ?? job.progress,
      startedAt: startedAt ?? job.startedAt,
      completedAt: completedAt ?? job.completedAt,
      errorMessage: errorMessage ?? job.errorMessage,
    );
    await _dao.upsert(updated);
    _emit(updated);
  }

  /// Returns a stream of updates for a specific job.
  Stream<AIJob> watchJob(String jobId) async* {
    final existing = await _dao.getById(jobId);
    if (existing != null) yield existing;

    final controller = _jobControllers.putIfAbsent(
      jobId,
      () => StreamController<AIJob>.broadcast(),
    );
    yield* controller.stream;
  }

  /// Returns a stream of worker status updates.
  Stream<WorkerStatus> watchWorkerStatus() {
    return _statusController.stream;
  }

  /// Returns all pending jobs.
  Future<List<AIJob>> getPendingJobs() => _dao.getByStatus(AIJobStatus.pending);

  /// Returns all jobs regardless of status.
  Future<List<AIJob>> getAllJobs() => _dao.getAll();

  /// Cancels a pending job.
  Future<void> cancel(String jobId) async {
    final job = await _dao.getById(jobId);
    if (job == null || job.status != AIJobStatus.pending) return;

    final cancelled = job.copyWith(
      status: AIJobStatus.cancelled,
      completedAt: DateTime.now(),
    );
    await _dao.upsert(cancelled);
    _emit(cancelled);
    _logger.info('Cancelled AI job $jobId');
  }

  /// Manually triggers processing of a specific job.
  Future<void> processJob(String jobId) async {
    final replyPort = ReceivePort();
    try {
      final msg = ProcessJob(jobId: jobId);
      msg.replyPort = replyPort.sendPort;
      await _sendToWorker(msg);
    } finally {
      replyPort.close();
    }
  }

  /// Gets the current worker status.
  Future<WorkerStatus?> getWorkerStatus() async {
    final response = await _sendToWorker(GetStatus());
    return response.status;
  }

  void _emit(AIJob job) {
    final controller = _jobControllers[job.id];
    if (controller != null && !controller.isClosed) {
      controller.add(job);
    }
    if (job.status == AIJobStatus.completed ||
        job.status == AIJobStatus.failed ||
        job.status == AIJobStatus.cancelled) {
      final c = _jobControllers.remove(job.id);
      if (c != null && !c.isClosed) {
        c.close();
      }
    }
  }

  /// Shuts down the worker isolate and releases resources.
  Future<void> dispose() async {
    _logger.info('Disposing background job queue');

    if (_workerSendPort != null && _isInitialized) {
      final replyPort = ReceivePort();
      try {
        final msg = StopWorker();
        msg.replyPort = replyPort.sendPort;
        await _sendToWorker(msg);
      } finally {
        replyPort.close();
      }
    }

    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
    _workerReceivePort?.close();
    _workerReceivePort = null;

    for (final controller in _jobControllers.values) {
      await controller.close();
    }
    _jobControllers.clear();

    await _statusController.close();

    _isInitialized = false;
    _logger.info('Background job queue disposed');
  }
}