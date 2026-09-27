import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../../domain/models/ai_job.dart';

/// Data access object for the ai_jobs table.
class AiJobDao {
  AiJobDao(this._db);

  final Database _db;
  final _changeController = StreamController<void>.broadcast();

  /// Stream that emits whenever the ai_jobs table changes.
  Stream<void> get onChange => _changeController.stream;

  /// Notify listeners that the table changed. Called after inserts/updates.
  void _notify() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  /// Inserts or replaces a job record.
  Future<void> upsert(AIJob job) async {
    await _db.insert(
      'ai_jobs',
      _toRow(job),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  /// Returns a job by id, or null if not found.
  Future<AIJob?> getById(String id) async {
    final rows = await _db.query(
      'ai_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Returns all jobs with the given status, sorted by priority (highest first) then creation time.
  Future<List<AIJob>> getByStatus(AIJobStatus status) async {
    final rows = await _db.query(
      'ai_jobs',
      where: 'status = ?',
      whereArgs: [status.name],
      orderBy: 'priority DESC, created_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Returns a reactive stream of jobs with the given status.
  ///
  /// Re-queries whenever the table changes (inserts/updates).
  Stream<List<AIJob>> watchByStatus(AIJobStatus status) async* {
    // Emit initial state
    yield await getByStatus(status);

    // Re-query on every table change
    await for (final _ in _changeController.stream) {
      yield await getByStatus(status);
    }
  }

  /// Returns all jobs for a photo.
  Future<List<AIJob>> getByPhotoId(String photoId) async {
    final rows = await _db.query(
      'ai_jobs',
      where: 'photo_id = ?',
      whereArgs: [photoId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Returns pending or running jobs for a photo and type.
  /// Used to prevent duplicate job creation.
  Future<bool> hasActiveJobForPhoto(String photoId, AIJobType type) async {
    final rows = await _db.query(
      'ai_jobs',
      where: 'photo_id = ? AND type = ? AND status IN (?, ?)',
      whereArgs: [photoId, type.name, AIJobStatus.pending.name, AIJobStatus.running.name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Delete all jobs for a photo.
  Future<void> deleteByPhotoId(String photoId) async {
    await _db.delete('ai_jobs', where: 'photo_id = ?', whereArgs: [photoId]);
    _notify();
  }

  /// Returns all jobs regardless of status.
  Future<List<AIJob>> getAll() async {
    final rows = await _db.query('ai_jobs', orderBy: 'created_at DESC');
    return rows.map(_fromRow).toList();
  }

  /// Resets jobs stuck in 'running' state back to 'pending'.
  ///
  /// Jobs are considered stuck if they have been running for longer than
  /// [timeout]. This handles cases where the worker isolate crashed or
  /// was killed mid-processing.
  Future<int> resetStuckJobs({Duration timeout = const Duration(minutes: 10)}) async {
    final cutoff = DateTime.now().subtract(timeout).toIso8601String();
    final count = await _db.rawUpdate(
      "UPDATE ai_jobs SET status = 'pending', started_at = NULL, "
      'error_message = NULL '
      "WHERE status = 'running' AND started_at < ?",
      [cutoff],
    );
    if (count > 0) _notify();
    return count;
  }

  /// Increment retry count for a failed job.
  Future<void> incrementRetryCount(String jobId) async {
    await _db.rawUpdate(
      'UPDATE ai_jobs SET retry_count = retry_count + 1 WHERE id = ?',
      [jobId],
    );
    _notify();
  }

  void dispose() {
    _changeController.close();
  }

  Map<String, Object?> _toRow(AIJob job) => {
        'id': job.id,
        'type': job.type.name,
        'status': job.status.name,
        'photo_id': job.photoId,
        'progress': job.progress,
        'error_message': job.errorMessage,
        'created_at': job.createdAt.toIso8601String(),
        'started_at': job.startedAt?.toIso8601String(),
        'completed_at': job.completedAt?.toIso8601String(),
        'retry_count': job.retryCount,
        'priority': job.priority.value,
      };

  AIJob _fromRow(Map<String, Object?> row) {
    return AIJob(
      id: row['id'] as String,
      type: AIJobType.values.byName(row['type'] as String),
      status: AIJobStatus.values.byName(row['status'] as String),
      photoId: row['photo_id'] as String,
      progress: (row['progress'] as num).toDouble(),
      errorMessage: row['error_message'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      startedAt: row['started_at'] != null
          ? DateTime.parse(row['started_at'] as String)
          : null,
      completedAt: row['completed_at'] != null
          ? DateTime.parse(row['completed_at'] as String)
          : null,
      retryCount: (row['retry_count'] as int?) ?? 0,
      priority: AIJobPriority.values.firstWhere(
        (p) => p.value == ((row['priority'] as int?) ?? 1),
        orElse: () => AIJobPriority.normal,
      ),
    );
  }
}
