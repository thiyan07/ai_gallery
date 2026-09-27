import 'package:ai_gallery/domain/models/ocr.dart';
import 'package:sqflite/sqflite.dart';

/// DAO for OCR text extraction results.
class OcrDao {
  OcrDao(this._db);

  final Database _db;

  static const String tableName = 'ocr_text';

  /// Insert an OCR result.
  Future<void> insertOcr(OcrRecord record) async {
    final map = record.toMap();
    // Only add created_at if not already present
    if (!map.containsKey('created_at')) {
      map['created_at'] = DateTime.now().toIso8601String();
    }
    await _db.insert(
      tableName,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get OCR result by photo ID.
  Future<OcrRecord?> getOcrByPhotoId(String photoId) async {
    final rows = await _db.query(
      tableName,
      where: 'photo_id = ?',
      whereArgs: [photoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OcrRecord.fromMap(rows.first);
  }

  /// Delete OCR result by photo ID.
  Future<void> deleteOcrByPhotoId(String photoId) async {
    await _db.delete(
      tableName,
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
  }

  /// Search OCR text across photos.
  Future<List<OcrRecord>> searchOcrText(String query, {int limit = 20}) async {
    final rows = await _db.query(
      tableName,
      where: 'text LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(OcrRecord.fromMap).toList();
  }

  /// Search OCR text within a specific set of photo IDs.
  /// Used for person+OCR queries where we already know the candidate photo IDs.
  Future<List<OcrRecord>> searchOcrTextInPhotos(
    String query,
    List<String> photoIds, {
    int limit = 100,
  }) async {
    if (photoIds.isEmpty) return [];
    final placeholders = photoIds.map((_) => '?').join(',');
    final rows = await _db.query(
      tableName,
      where: 'text LIKE ? AND photo_id IN ($placeholders)',
      whereArgs: ['%$query%', ...photoIds],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(OcrRecord.fromMap).toList();
  }
}