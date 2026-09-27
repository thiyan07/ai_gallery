import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import '../database/app_database.dart';
import '../logging/app_logger.dart';

/// Result of a reconciliation check.
class ReconciliationResult {
  const ReconciliationResult({
    required this.orphanedInDb,
    required this.missingFromDb,
    required this.totalDbPhotos,
    required this.totalMediaPhotos,
    this.warnings = const [],
  });

  /// Photo IDs in database but not in device media.
  final List<String> orphanedInDb;

  /// Photo IDs on device but not in database.
  final List<String> missingFromDb;

  final int totalDbPhotos;
  final int totalMediaPhotos;
  final List<String> warnings;

  int get orphanedCount => orphanedInDb.length;
  int get missingCount => missingFromDb.length;
  bool get isHealthy => orphanedCount == 0 && missingCount == 0;

  Map<String, dynamic> toJson() => {
        'orphanedInDb': orphanedInDb.length,
        'missingFromDb': missingFromDb.length,
        'totalDbPhotos': totalDbPhotos,
        'totalMediaPhotos': totalMediaPhotos,
        'isHealthy': isHealthy,
        'warnings': warnings,
      };
}

/// Reconciles the database photo_metadata table with actual device media.
///
/// Detects:
/// - Photos in DB that no longer exist on device (orphaned)
/// - Photos on device not yet in DB (missing from index)
///
/// Can optionally clean up orphaned records (with user confirmation).
class MediaReconciler {
  MediaReconciler({
    required AppDatabase database,
    required AppLogger logger,
  })  : _db = database,
        _logger = logger;

  final AppDatabase _db;
  final AppLogger _logger;

  /// Reconciles database state with actual device media.
  ///
  /// [existingIds] is the set of photo IDs currently on the device.
  /// If null, fetches from photo_manager.
  Future<ReconciliationResult> reconcile({
    Set<String>? existingIds,
  }) async {
    _logger.info('Starting media reconciliation');

    // Get all photo IDs from database
    final dbRows = await _db.database.rawQuery(
      'SELECT photo_id FROM photo_metadata',
    );
    final dbIds = dbRows.map((r) => r['photo_id'] as String).toSet();

    // Get device media IDs if not provided
    Set<String> deviceIds;
    if (existingIds != null) {
      deviceIds = existingIds;
    } else {
      deviceIds = await _fetchDeviceMediaIds();
    }

    // Find orphans (in DB but not on device)
    final orphaned = dbIds.difference(deviceIds).toList()..sort();

    // Find missing (on device but not in DB)
    final missing = deviceIds.difference(dbIds).toList()..sort();

    final warnings = <String>[];
    if (orphaned.length > 100) {
      warnings.add(
        'Large number of orphaned DB records: ${orphaned.length}',
      );
    }

    _logger.info(
      'Reconciliation: ${orphaned.length} orphaned, '
      '${missing.length} missing, '
      '${dbIds.length} in DB, ${deviceIds.length} on device',
    );

    return ReconciliationResult(
      orphanedInDb: orphaned,
      missingFromDb: missing,
      totalDbPhotos: dbIds.length,
      totalMediaPhotos: deviceIds.length,
      warnings: warnings,
    );
  }

  /// Removes orphaned records from the database.
  ///
  /// WARNING: This permanently deletes analysis data for photos no longer on device.
  /// Only call after user confirmation.
  Future<int> cleanOrphaned(List<String> orphanedIds) async {
    if (orphanedIds.isEmpty) return 0;

    _logger.info('Cleaning ${orphanedIds.length} orphaned records');
    int totalDeleted = 0;

    // Process in batches of 100 to avoid SQLite limits
    const batchSize = 100;
    for (var i = 0; i < orphanedIds.length; i += batchSize) {
      final batch = orphanedIds.skip(i).take(batchSize).toList();
      final placeholders = batch.map((_) => '?').join(',');

      // Delete from all related tables
      await _db.database.rawDelete(
        'DELETE FROM photo_metadata WHERE photo_id IN ($placeholders)',
        batch,
      );
      await _db.database.rawDelete(
        'DELETE FROM analysis_state WHERE photo_id IN ($placeholders)',
        batch,
      );
      await _db.database.rawDelete(
        'DELETE FROM embeddings WHERE photo_id IN ($placeholders)',
        batch,
      );
      await _db.database.rawDelete(
        'DELETE FROM object_tags WHERE photo_id IN ($placeholders)',
        batch,
      );
      await _db.database.rawDelete(
        'DELETE FROM ocr_text WHERE photo_id IN ($placeholders)',
        batch,
      );
      await _db.database.rawDelete(
        'DELETE FROM faces WHERE photo_id IN ($placeholders)',
        batch,
      );
      await _db.database.rawDelete(
        'DELETE FROM ai_jobs WHERE photo_id IN ($placeholders)',
        batch,
      );
      totalDeleted += batch.length;
    }

    _logger.info('Cleaned $totalDeleted orphaned records');
    return totalDeleted;
  }

  /// Fetches all media IDs from the device.
  Future<Set<String>> _fetchDeviceMediaIds() async {
    try {
      final albums = await PhotoManager.getAssetPathList(type: RequestType.all);
      if (albums.isEmpty) return {};

      final allIds = <String>{};
      for (final album in albums) {
        final count = await album.assetCountAsync;
        if (count == 0) continue;

        final assets = await album.getAssetListRange(start: 0, end: count);
        for (final asset in assets) {
          allIds.add(asset.id);
        }
      }
      return allIds;
    } catch (e) {
      _logger.warning('Failed to fetch device media IDs: $e');
      return {};
    }
  }
}
