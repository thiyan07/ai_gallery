import 'package:ai_gallery/domain/models/embedding.dart';
import 'package:sqflite/sqflite.dart';

/// DAO for image embeddings (vector representations).
class EmbeddingDao {
  EmbeddingDao(this._db);

  final Database _db;

  static const String tableName = 'embeddings';

  /// Insert an embedding record.
  Future<void> insertEmbedding(EmbeddingRecord record) async {
    await _db.insert(
      tableName,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get embedding by photo ID.
  Future<EmbeddingRecord?> getEmbeddingByPhotoId(String photoId) async {
    final rows = await _db.query(
      tableName,
      where: 'photo_id = ?',
      whereArgs: [photoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return EmbeddingRecord.fromMap(rows.first);
  }

  /// Get all embeddings (for similarity search).
  Future<List<EmbeddingRecord>> getAllEmbeddings({int limit = 10000}) async {
    final rows = await _db.query(
      tableName,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(EmbeddingRecord.fromMap).toList();
  }

  /// Delete embedding by photo ID.
  Future<void> deleteEmbeddingByPhotoId(String photoId) async {
    await _db.delete(
      tableName,
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
  }

  /// Get embedding count.
  Future<int> countEmbeddings() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get per-region embeddings for a photo.
  Future<List<EmbeddingRecord>> getRegionEmbeddingsByPhotoId(String photoId) async {
    final rows = await _db.query(
      tableName,
      where: 'photo_id = ? AND region_label IS NOT NULL',
      whereArgs: [photoId],
    );
    return rows.map(EmbeddingRecord.fromMap).toList();
  }

  /// Count per-region embeddings for a photo.
  Future<int> countRegionsByPhotoId(String photoId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName WHERE photo_id = ? AND region_label IS NOT NULL',
      [photoId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete per-region embeddings for a photo (keeps the global row).
  Future<void> deleteRegionsByPhotoId(String photoId) async {
    await _db.delete(
      tableName,
      where: 'photo_id = ? AND region_label IS NOT NULL',
      whereArgs: [photoId],
    );
  }
}