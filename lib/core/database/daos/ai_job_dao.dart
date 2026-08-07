import 'package:sqflite/sqflite.dart';

import '../../../domain/models/ai_job.dart';

/// Data access object for the ai_jobs table.
class AiJobDao {
  const AiJobDao(this._db);

  final Database _db;

  /// Inserts or replaces a job record.
  Future<void> upsert(AIJob job) async {
    await _db.insert(
      'ai_jobs',
      _toRow(job),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  /// Returns all jobs with the given status.
  Future<List<AIJob>> getByStatus(AIJobStatus status) async {
    final rows = await _db.query(
      'ai_jobs',
      where: 'status = ?',
      whereArgs: [status.name],
      orderBy: 'created_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Returns a stream of jobs with the given status, updated on database changes.
  Stream<List<AIJob>> watchByStatus(AIJobStatus status) {
    return _db
        .query(
          'ai_jobs',
          where: 'status = ?',
          whereArgs: [status.name],
          orderBy: 'created_at ASC',
        )
        .asStream()
        .map((rows) => rows.map(_fromRow).toList());
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

  /// Returns all jobs regardless of status.
  Future<List<AIJob>> getAll() async {
    final rows = await _db.query('ai_jobs', orderBy: 'created_at DESC');
    return rows.map(_fromRow).toList();
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
    );
  }
}
