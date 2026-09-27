import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/database/daos/trash_dao.dart';
import 'package:ai_gallery/features/gallery/services/media_service.dart';

/// Recycle bin flows: trash/restore/permanent-delete/purge.
///
/// Trashed assets stay in MediaStore (so restore is lossless, including all
/// AI index rows) but are hidden from grids via [trashedIds].
class TrashService {
  TrashService({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  /// Move assets to trash (reversible for [TrashDao.retention]).
  Future<void> moveToTrash(List<String> assetIds, {String? mediaType}) async {
    await _db.trash.moveToTrash(assetIds, mediaType: mediaType);
    // Opportunistically purge anything past retention.
    await purgeExpired();
  }

  /// Restore trashed assets to the library.
  Future<void> restore(List<String> assetIds) => _db.trash.restore(assetIds);

  /// Permanently delete assets: MediaStore + trash tracking + AI index rows.
  /// Returns the number of assets deleted from MediaStore.
  Future<int> deletePermanently(List<String> assetIds) async {
    if (assetIds.isEmpty) return 0;
    final deleted = await MediaService.deleteAssets(assetIds);
    // Drop tracking + index rows for assets actually gone. Keep tracking for
    // anything the OS refused to delete so it stays hidden, not resurrected.
    await _db.trash.removePermanently(assetIds);
    await deleteIndexRows(assetIds);
    return deleted;
  }

  /// Permanently delete everything in trash.
  Future<int> emptyTrash() async {
    final entries = await _db.trash.entries();
    return deletePermanently(entries.map((e) => e.assetId).toList());
  }

  /// Permanently delete items past retention. Returns deleted count.
  Future<int> purgeExpired() async {
    final expired = await _db.trash.purgeExpired();
    if (expired.isEmpty) return 0;
    final deleted = await MediaService.deleteAssets(expired);
    await deleteIndexRows(expired);
    return deleted;
  }

  /// IDs currently hidden from grids.
  Future<Set<String>> trashedIds() => _db.trash.trashedIds();

  /// Trash contents, newest first.
  Future<List<TrashEntry>> entries() => _db.trash.entries();

  /// Remove AI index + metadata rows (shared by delete flows).
  Future<void> deleteIndexRows(List<String> assetIds) async {
    if (assetIds.isEmpty) return;
    final placeholders = assetIds.map((_) => '?').join(',');
    await _db.database.delete('photo_metadata',
        where: 'photo_id IN ($placeholders)', whereArgs: assetIds);
    await _db.database.delete('embeddings',
        where: 'photo_id IN ($placeholders)', whereArgs: assetIds);
    await _db.database.delete('faces',
        where: 'photo_id IN ($placeholders)', whereArgs: assetIds);
    await _db.database.delete('object_tags',
        where: 'photo_id IN ($placeholders)', whereArgs: assetIds);
    await _db.database.delete('ocr_text',
        where: 'photo_id IN ($placeholders)', whereArgs: assetIds);
    await _db.database.delete('favorites',
        where: 'asset_id IN ($placeholders)', whereArgs: assetIds);
    await _db.database.delete('edit_recipes',
        where: 'photo_id IN ($placeholders)', whereArgs: assetIds);
    await _db.database.delete('analysis_state',
        where: 'photo_id IN ($placeholders)', whereArgs: assetIds);
  }
}
