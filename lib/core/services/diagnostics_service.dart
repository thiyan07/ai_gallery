import 'dart:async';

import '../database/app_database.dart';
import '../logging/app_logger.dart';
import '../../domain/models/ai_job.dart';

/// Diagnostic information about the system state.
class DiagnosticReport {
  const DiagnosticReport({
    required this.timestamp,
    required this.databaseStats,
    required this.jobStats,
    required this.analysisStats,
    this.warnings = const [],
  });

  final DateTime timestamp;
  final DatabaseStats databaseStats;
  final JobStats jobStats;
  final AnalysisStats analysisStats;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'database': databaseStats.toJson(),
        'jobs': jobStats.toJson(),
        'analysis': analysisStats.toJson(),
        'warnings': warnings,
      };
}

class DatabaseStats {
  const DatabaseStats({
    required this.tableCount,
    required this.photoCount,
    required this.faceCount,
    required this.embeddingCount,
    required this.objectTagCount,
    required this.ocrTextCount,
    required this.knowledgeEntityCount,
    required this.knowledgeRelationshipCount,
    required this.dbSizeBytes,
  });

  final int tableCount;
  final int photoCount;
  final int faceCount;
  final int embeddingCount;
  final int objectTagCount;
  final int ocrTextCount;
  final int knowledgeEntityCount;
  final int knowledgeRelationshipCount;
  final int dbSizeBytes;

  Map<String, dynamic> toJson() => {
        'tableCount': tableCount,
        'photoCount': photoCount,
        'faceCount': faceCount,
        'embeddingCount': embeddingCount,
        'objectTagCount': objectTagCount,
        'ocrTextCount': ocrTextCount,
        'knowledgeEntityCount': knowledgeEntityCount,
        'knowledgeRelationshipCount': knowledgeRelationshipCount,
        'dbSizeBytes': dbSizeBytes,
      };
}

class JobStats {
  const JobStats({
    required this.pending,
    required this.running,
    required this.completed,
    required this.failed,
    required this.cancelled,
  });

  final int pending;
  final int running;
  final int completed;
  final int failed;
  final int cancelled;

  int get total => pending + running + completed + failed + cancelled;

  Map<String, dynamic> toJson() => {
        'pending': pending,
        'running': running,
        'completed': completed,
        'failed': failed,
        'cancelled': cancelled,
        'total': total,
      };
}

class AnalysisStats {
  const AnalysisStats({
    required this.totalPhotos,
    required this.analyzedPhotos,
    required this.unanalyzedPhotos,
    required this.analysisCoverage,
    required this.lastAnalyzedAt,
  });

  final int totalPhotos;
  final int analyzedPhotos;
  final int unanalyzedPhotos;
  final double analysisCoverage;
  final DateTime? lastAnalyzedAt;

  Map<String, dynamic> toJson() => {
        'totalPhotos': totalPhotos,
        'analyzedPhotos': analyzedPhotos,
        'unanalyzedPhotos': unanalyzedPhotos,
        'analysisCoverage': analysisCoverage.toStringAsFixed(2),
        'lastAnalyzedAt': lastAnalyzedAt?.toIso8601String(),
      };
}

/// Collects diagnostic information about the system.
class DiagnosticsService {
  DiagnosticsService({
    required AppDatabase database,
    required AppLogger logger,
  })  : _db = database,
        _logger = logger;

  final AppDatabase _db;
  final AppLogger _logger;

  /// Generates a comprehensive diagnostic report.
  Future<DiagnosticReport> generateReport() async {
    _logger.info('Generating diagnostic report');
    final warnings = <String>[];

    final dbStats = await _collectDatabaseStats();
    final jobStats = await _collectJobStats();
    final analysisStats = await _collectAnalysisStats(warnings);

    return DiagnosticReport(
      timestamp: DateTime.now(),
      databaseStats: dbStats,
      jobStats: jobStats,
      analysisStats: analysisStats,
      warnings: warnings,
    );
  }

  Future<DatabaseStats> _collectDatabaseStats() async {
    final tableResult = await _db.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );

    final photoCount = await _countTable('photo_metadata');
    final faceCount = await _countTable('faces');
    final embeddingCount = await _countTable('embeddings');
    final objectTagCount = await _countTable('object_tags');
    final ocrTextCount = await _countTable('ocr_text');
    final kgEntityCount = await _countTable('knowledge_graph_entities');
    final kgRelCount = await _countTable('knowledge_graph_relationships');

    // Estimate DB size
    int dbSizeBytes = 0;
    try {
      final pagesResult =
          await _db.database.rawQuery('PRAGMA page_count');
      final pageSizeResult =
          await _db.database.rawQuery('PRAGMA page_size');
      if (pagesResult.isNotEmpty && pageSizeResult.isNotEmpty) {
        dbSizeBytes = (pagesResult.first['page_count'] as int) *
            (pageSizeResult.first['page_size'] as int);
      }
    } catch (e) {
      _logger.debug('Failed to estimate DB size: $e');
    }

    return DatabaseStats(
      tableCount: tableResult.length,
      photoCount: photoCount,
      faceCount: faceCount,
      embeddingCount: embeddingCount,
      objectTagCount: objectTagCount,
      ocrTextCount: ocrTextCount,
      knowledgeEntityCount: kgEntityCount,
      knowledgeRelationshipCount: kgRelCount,
      dbSizeBytes: dbSizeBytes,
    );
  }

  Future<JobStats> _collectJobStats() async {
    return JobStats(
      pending: (await _db.aiJobs.getByStatus(AIJobStatus.pending)).length,
      running: (await _db.aiJobs.getByStatus(AIJobStatus.running)).length,
      completed: (await _db.aiJobs.getByStatus(AIJobStatus.completed)).length,
      failed: (await _db.aiJobs.getByStatus(AIJobStatus.failed)).length,
      cancelled: (await _db.aiJobs.getByStatus(AIJobStatus.cancelled)).length,
    );
  }

  Future<AnalysisStats> _collectAnalysisStats(List<String> warnings) async {
    final totalPhotos = await _countTable('photo_metadata');

    int analyzedPhotos = 0;
    try {
      final result = await _db.database.rawQuery(
        'SELECT COUNT(*) as c FROM analysis_state WHERE analyzed_at IS NOT NULL',
      );
      analyzedPhotos = (result.first['c'] as int?) ?? 0;
    } catch (e) {
      _logger.debug('Failed to count analyzed photos: $e');
    }

    final unanalyzed = totalPhotos - analyzedPhotos;
    final coverage =
        totalPhotos > 0 ? analyzedPhotos / totalPhotos : 0.0;

    DateTime? lastAnalyzed;
    try {
      final result = await _db.database.rawQuery(
        'SELECT MAX(analyzed_at) as last FROM analysis_state',
      );
      final lastStr = result.first['last'] as String?;
      if (lastStr != null) lastAnalyzed = DateTime.tryParse(lastStr);
    } catch (e) {
      _logger.debug('Failed to get last analyzed timestamp: $e');
    }

    if (coverage < 0.5 && totalPhotos > 10) {
      warnings.add(
        'Analysis coverage is low: ${(coverage * 100).toStringAsFixed(1)}% '
        '($analyzedPhotos/$totalPhotos photos analyzed)',
      );
    }

    return AnalysisStats(
      totalPhotos: totalPhotos,
      analyzedPhotos: analyzedPhotos,
      unanalyzedPhotos: unanalyzed,
      analysisCoverage: coverage,
      lastAnalyzedAt: lastAnalyzed,
    );
  }

  Future<int> _countTable(String table) async {
    try {
      final result = await _db.database.rawQuery('SELECT COUNT(*) as c FROM $table');
      return (result.first['c'] as int?) ?? 0;
    } catch (e) {
      _logger.debug('Failed to count table $table: $e');
      return 0;
    }
  }
}
