import 'dart:typed_data';

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
}