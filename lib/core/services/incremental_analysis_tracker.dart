import 'dart:async';

import '../database/app_database.dart';

/// Tracks analysis versioning to avoid re-analyzing photos when
/// the analysis pipeline hasn't changed.
///
/// Each analysis stage (face detection, object tagging, embedding, etc.)
/// has a version string. When the version changes, all photos need
/// re-analysis for that stage. When unchanged, only new/modified photos
/// are analyzed.
class IncrementalAnalysisTracker {
  IncrementalAnalysisTracker({
    required AppDatabase database,
  })  : _db = database;

  final AppDatabase _db;

  /// Current analysis version for each stage.
  static const currentVersions = {
    'face_detection': '1.1',
    'object_tagging': '1.0',
    'embedding': '1.0',
    'ocr': '1.0',
    'quality_scoring': '1.0',
    'knowledge_graph': '1.0',
  };

  /// Checks if a photo needs analysis for a given stage.
  ///
  /// Returns true if:
  /// - The photo has no analysis_state record, OR
  /// - The photo's analysis_version for this stage is outdated, OR
  /// - The photo has been modified since last analysis
  Future<bool> needsAnalysis(
    String photoId,
    String stage, {
    DateTime? modifiedAfter,
  }) async {
    final currentVersion = currentVersions[stage];
    if (currentVersion == null) return true;

    final state = await _db.analysisState.getByPhotoId(photoId);
    if (state == null) return true;

    // Check if analysis_version column stores stage versions
    // For now, use a simple version comparison
    if (state.analysisVersion != currentVersion) return true;

    // Check if photo was modified after last analysis
    if (modifiedAfter != null && state.analyzedAt != null) {
      if (modifiedAfter.isAfter(state.analyzedAt!)) return true;
    }

    return false;
  }

  /// Returns photo IDs that need analysis for a given stage.
  Future<List<String>> getPhotosNeedingAnalysis(
    String stage, {
    int limit = 100,
  }) async {
    final currentVersion = currentVersions[stage];
    if (currentVersion == null) return [];

    final rows = await _db.database.rawQuery('''
      SELECT p.photo_id
      FROM photo_metadata p
      LEFT JOIN analysis_state a ON p.photo_id = a.photo_id
      WHERE a.photo_id IS NULL
         OR a.analysis_version != ?
         OR a.analyzed_at IS NULL
      ORDER BY p.date_created DESC
      LIMIT ?
    ''', [currentVersion, limit]);

    return rows.map((r) => r['photo_id'] as String).toList();
  }

  /// Marks a photo as analyzed for a specific stage.
  Future<void> markAnalyzed(
    String photoId,
    String stage, {
    Map<String, dynamic>? metadata,
  }) async {
    final currentVersion = currentVersions[stage];
    if (currentVersion == null) return;

    final existing = await _db.analysisState.getByPhotoId(photoId);

    // Update or create analysis state
    if (existing != null) {
      await _db.database.rawUpdate('''
        UPDATE analysis_state
        SET analysis_version = ?, analyzed_at = ?
        WHERE photo_id = ?
      ''', [currentVersion, DateTime.now().toIso8601String(), photoId]);
    } else {
      await _db.database.rawInsert('''
        INSERT OR REPLACE INTO analysis_state
          (photo_id, analysis_version, analyzed_at, completed_stages)
        VALUES (?, ?, ?, 0)
      ''', [photoId, currentVersion, DateTime.now().toIso8601String()]);
    }
  }

  /// Returns the analysis coverage percentage.
  Future<double> getCoverage() async {
    final totalResult =
        await _db.database.rawQuery('SELECT COUNT(*) as c FROM photo_metadata');
    final total = (totalResult.first['c'] as int?) ?? 0;
    if (total == 0) return 0.0;

    final analyzedResult = await _db.database.rawQuery(
      'SELECT COUNT(*) as c FROM analysis_state WHERE analyzed_at IS NOT NULL',
    );
    final analyzed = (analyzedResult.first['c'] as int?) ?? 0;

    return analyzed / total;
  }

  /// Returns analysis statistics per stage.
  Future<Map<String, int>> getStageStats() async {
    final stats = <String, int>{};
    for (final stage in currentVersions.keys) {
      stats[stage] = await _countNeedingAnalysis(stage);
    }
    return stats;
  }

  Future<int> _countNeedingAnalysis(String stage) async {
    final currentVersion = currentVersions[stage];
    if (currentVersion == null) return 0;

    final result = await _db.database.rawQuery('''
      SELECT COUNT(*) as c
      FROM photo_metadata p
      LEFT JOIN analysis_state a ON p.photo_id = a.photo_id
      WHERE a.photo_id IS NULL
         OR a.analysis_version != ?
         OR a.analyzed_at IS NULL
    ''', [currentVersion]);

    return (result.first['c'] as int?) ?? 0;
  }
}
