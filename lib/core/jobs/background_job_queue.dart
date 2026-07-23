import 'dart:async';

import '../../../domain/models/ai_job.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/daos/ai_job_dao.dart';
import '../../../core/logging/app_logger.dart';

/// Callback invoked to process a single AI job off the UI thread.
typedef AIJobProcessor = Future<void> Function(AIJob job);

/// In-process background job queue backed by SQLite persistence.
class BackgroundJobQueue {
  BackgroundJobQueue({
    required AppDatabase database,
    required AppLogger logger,
    AIJobProcessor? processor,
  })  : _dao = database.aiJobs,
        _logger = logger,
        _processor = processor ?? _noopProcessor;

  final AiJobDao _dao;
  final AppLogger _logger;
  final AIJobProcessor _processor;

  bool _isProcessing = false;
  final _jobControllers = <String, StreamController<AIJob>>{};

  static Future<void> _noopProcessor(AIJob job) async {}

  /// Enqueues a new job and starts processing if idle.
  Future<void> enqueue(AIJob job) async {
    await _dao.upsert(job);
    _emit(job);
    _logger.info('Enqueued AI job ${job.id} (${job.type.name})');
    unawaited(_processNext());
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

  /// Returns all pending jobs.
  Future<List<AIJob>> getPendingJobs() => _dao.getByStatus(AIJobStatus.pending);

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

  Future<void> _processNext() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final pending = await _dao.getByStatus(AIJobStatus.pending);
        if (pending.isEmpty) break;

        final job = pending.first;
        final running = job.copyWith(
          status: AIJobStatus.running,
          startedAt: DateTime.now(),
        );
        await _dao.upsert(running);
        _emit(running);

        try {
          await _processor(running);
          final completed = running.copyWith(
            status: AIJobStatus.completed,
            progress: 1.0,
            completedAt: DateTime.now(),
          );
          await _dao.upsert(completed);
          _emit(completed);
        } catch (e, st) {
          _logger.error('AI job ${job.id} failed', error: e, stackTrace: st);
          final failed = running.copyWith(
            status: AIJobStatus.failed,
            errorMessage: e.toString(),
            completedAt: DateTime.now(),
          );
          await _dao.upsert(failed);
          _emit(failed);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  void _emit(AIJob job) {
    final controller = _jobControllers[job.id];
    if (controller != null && !controller.isClosed) {
      controller.add(job);
    }
  }

  /// Releases stream controllers (for tests).
  void dispose() {
    for (final controller in _jobControllers.values) {
      controller.close();
    }
    _jobControllers.clear();
  }
}