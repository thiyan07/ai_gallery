import 'dart:async';

import '../database/app_database.dart';
import '../logging/app_logger.dart';

/// Result of a repair operation.
class RepairResult {
  const RepairResult({
    required this.repairType,
    required this.success,
    this.itemsAffected = 0,
    this.message,
  });

  final String repairType;
  final bool success;
  final int itemsAffected;
  final String? message;
}

/// Automatically repairs common database/state issues.
///
/// Repairs performed:
/// - Reset stuck jobs (running > 10 minutes with no progress)
/// - Clean orphaned analysis_state records
/// - Clean orphaned knowledge graph entries
/// - Reset failed jobs for retry
class RepairEngine {
  RepairEngine({
    required AppDatabase database,
    required AppLogger logger,
  })  : _db = database,
        _logger = logger;

  final AppDatabase _db;
  final AppLogger _logger;

  /// Runs all repairs and returns results.
  Future<List<RepairResult>> runAllRepairs() async {
    _logger.info('Starting automatic repairs');
    final results = <RepairResult>[];

    results.add(await repairStuckJobs());
    results.add(await repairOrphanedAnalysis());
    results.add(await repairOrphanedGraphEntities());
    results.add(await cleanOldErrorMessages());

    final totalAffected =
        results.fold<int>(0, (sum, r) => sum + r.itemsAffected);
    _logger.info(
      'Repairs complete: ${results.length} operations, '
      '$totalAffected items affected',
    );

    return results;
  }

  /// Resets jobs stuck in 'running' state back to 'pending'.
  Future<RepairResult> repairStuckJobs() async {
    try {
      final count = await _db.aiJobs.resetStuckJobs(
        timeout: const Duration(minutes: 10),
      );
      return RepairResult(
        repairType: 'stuck_jobs',
        success: true,
        itemsAffected: count,
        message: count > 0 ? 'Reset $count stuck jobs' : 'No stuck jobs',
      );
    } catch (e) {
      return RepairResult(
        repairType: 'stuck_jobs',
        success: false,
        message: 'Failed: $e',
      );
    }
  }

  /// Removes analysis_state records for photos that no longer exist in photo_metadata.
  Future<RepairResult> repairOrphanedAnalysis() async {
    try {
      final orphaned = await _db.database.rawQuery('''
        SELECT a.photo_id
        FROM analysis_state a
        LEFT JOIN photo_metadata p ON a.photo_id = p.photo_id
        WHERE p.photo_id IS NULL
      ''');

      if (orphaned.isEmpty) {
        return const RepairResult(
          repairType: 'orphaned_analysis',
          success: true,
          message: 'No orphaned analysis records',
        );
      }

      final batch = _db.database.batch();
      for (final row in orphaned) {
        batch.delete(
          'analysis_state',
          where: 'photo_id = ?',
          whereArgs: [row['photo_id']],
        );
      }
      await batch.commit(noResult: true);

      return RepairResult(
        repairType: 'orphaned_analysis',
        success: true,
        itemsAffected: orphaned.length,
        message: 'Removed ${orphaned.length} orphaned analysis records',
      );
    } catch (e) {
      return RepairResult(
        repairType: 'orphaned_analysis',
        success: false,
        message: 'Failed: $e',
      );
    }
  }

  /// Removes knowledge graph entities for photos/people/events that no longer exist.
  Future<RepairResult> repairOrphanedGraphEntities() async {
    try {
      // Remove orphaned media entities
      final orphanedMedia = await _db.database.rawQuery('''
        SELECT e.id
        FROM knowledge_graph_entities e
        WHERE e.type = 'media'
        AND NOT EXISTS (
          SELECT 1 FROM photo_metadata p WHERE p.photo_id = e.external_id
        )
      ''');

      // Remove orphaned relationships referencing deleted entities
      final orphanedRels = await _db.database.rawQuery('''
        SELECT r.id
        FROM knowledge_graph_relationships r
        WHERE NOT EXISTS (
          SELECT 1 FROM knowledge_graph_entities e
          WHERE e.type || ':' || e.external_id = r.source_entity_id
          OR e.type || ':' || e.external_id = r.target_entity_id
        )
      ''');

      int totalAffected = 0;

      if (orphanedMedia.isNotEmpty) {
        final batch = _db.database.batch();
        for (final row in orphanedMedia) {
          batch.delete(
            'knowledge_graph_entities',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        await batch.commit(noResult: true);
        totalAffected += orphanedMedia.length;
      }

      if (orphanedRels.isNotEmpty) {
        final batch = _db.database.batch();
        for (final row in orphanedRels) {
          batch.delete(
            'knowledge_graph_relationships',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        await batch.commit(noResult: true);
        totalAffected += orphanedRels.length;
      }

      return RepairResult(
        repairType: 'orphaned_graph',
        success: true,
        itemsAffected: totalAffected,
        message: totalAffected > 0
            ? 'Removed $totalAffected orphaned graph entries'
            : 'No orphaned graph entries',
      );
    } catch (e) {
      return RepairResult(
        repairType: 'orphaned_graph',
        success: false,
        message: 'Failed: $e',
      );
    }
  }

  /// Truncates long error messages in failed jobs (prevents DB bloat).
  Future<RepairResult> cleanOldErrorMessages() async {
    try {
      // Truncate error messages longer than 1000 characters
      final count = await _db.database.rawUpdate('''
        UPDATE ai_jobs
        SET error_message = SUBSTR(error_message, 1, 1000) || '... [truncated]'
        WHERE LENGTH(error_message) > 1000
      ''');

      return RepairResult(
        repairType: 'truncate_errors',
        success: true,
        itemsAffected: count,
        message: count > 0 ? 'Truncated $count long error messages' : 'No messages to truncate',
      );
    } catch (e) {
      return RepairResult(
        repairType: 'truncate_errors',
        success: false,
        message: 'Failed: $e',
      );
    }
  }
}
