import 'package:sqflite/sqflite.dart';

/// DAO for the recycle bin (soft-deleted assets with 30-day retention).
///
/// Trashed assets stay in MediaStore but are hidden from grids; permanent
/// deletion happens on purge (after retention) or explicit empty/restore.
class TrashDao {
  TrashDao(this._db);

  final Database _db;

  static const String tableName = 'trash';

  /// Retention period before automatic permanent deletion.
  static const retention = Duration(days: 30);

  /// Move assets to trash.
  Future<void> moveToTrash(List<String> assetIds, {String? mediaType}) async {
    if (assetIds.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final batch = _db.batch();
    for (final id in assetIds) {
      batch.insert(
        tableName,
        {'asset_id': id, 'media_type': mediaType, 'deleted_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Restore assets from trash.
  Future<void> restore(List<String> assetIds) async {
    if (assetIds.isEmpty) return;
    final placeholders = assetIds.map((_) => '?').join(',');
    await _db.delete(
      tableName,
      where: 'asset_id IN ($placeholders)',
      whereArgs: assetIds,
    );
  }

  /// Permanently remove assets from trash tracking (after MediaStore delete).
  Future<void> removePermanently(List<String> assetIds) => restore(assetIds);

  /// All trashed asset IDs.
  Future<Set<String>> trashedIds() async {
    final rows = await _db.query(tableName, columns: ['asset_id']);
    return rows.map((r) => r['asset_id'] as String).toSet();
  }

  /// Trashed entries with age info, newest first.
  Future<List<TrashEntry>> entries() async {
    final rows = await _db.query(tableName, orderBy: 'deleted_at DESC');
    return rows.map(TrashEntry.fromMap).toList();
  }

  /// Delete tracking rows older than [retention]; returns their asset IDs so
  /// callers can permanently delete them from MediaStore.
  Future<List<String>> purgeExpired({DateTime? now}) async {
    final cutoff =
        (now ?? DateTime.now()).subtract(retention).toIso8601String();
    final rows = await _db.query(
      tableName,
      columns: ['asset_id'],
      where: 'deleted_at <= ?',
      whereArgs: [cutoff],
    );
    final ids = rows.map((r) => r['asset_id'] as String).toList();
    if (ids.isNotEmpty) {
      final placeholders = ids.map((_) => '?').join(',');
      await _db.delete(
        tableName,
        where: 'asset_id IN ($placeholders)',
        whereArgs: ids,
      );
    }
    return ids;
  }

  /// Whether an asset is trashed.
  Future<bool> isTrashed(String assetId) async {
    final rows = await _db.query(
      tableName,
      columns: ['asset_id'],
      where: 'asset_id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}

/// One trashed asset with its deletion timestamp.
class TrashEntry {
  const TrashEntry({
    required this.assetId,
    this.mediaType,
    required this.deletedAt,
  });

  final String assetId;
  final String? mediaType;
  final DateTime deletedAt;

  /// Days remaining before automatic permanent deletion.
  int daysLeft({DateTime? now}) {
    final expiry = deletedAt.add(TrashDao.retention);
    return expiry.difference(now ?? DateTime.now()).inDays.clamp(0, 30);
  }

  factory TrashEntry.fromMap(Map<String, Object?> map) => TrashEntry(
        assetId: map['asset_id'] as String,
        mediaType: map['media_type'] as String?,
        deletedAt: DateTime.parse(map['deleted_at'] as String),
      );
}
