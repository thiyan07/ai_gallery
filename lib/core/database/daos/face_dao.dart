import 'package:ai_gallery/domain/models/face_detection.dart';
import 'package:sqflite/sqflite.dart';

/// DAO for face detection results.
class FaceDao {
  FaceDao(this._db);

  final Database _db;

  static const String tableName = 'faces';

  /// Insert or replace a face detection.
  Future<void> insertFace(FaceDetectionRecord face) async {
    await _db.insert(
      tableName,
      face.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert multiple faces in a batch.
  Future<void> insertFaces(List<FaceDetectionRecord> faces) async {
    final batch = _db.batch();
    for (final face in faces) {
      batch.insert(
        tableName,
        face.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get faces by photo ID.
  Future<List<FaceDetectionRecord>> getFacesByPhotoId(String photoId) async {
    final rows = await _db.query(
      tableName,
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
    return rows.map(FaceDetectionRecord.fromMap).toList();
  }

  /// Get all faces that have embeddings (for clustering).
  Future<List<FaceDetectionRecord>> getFacesWithEmbeddings({
    int limit = 1000,
    int offset = 0,
  }) async {
    final rows = await _db.query(
      tableName,
      where: 'embedding IS NOT NULL AND embedding != ?',
      whereArgs: [[]],
      limit: limit,
      offset: offset,
    );
    return rows.map(FaceDetectionRecord.fromMap).toList();
  }

  /// Get all faces that have been clustered (have a label).
  Future<List<FaceDetectionRecord>> getClusteredFaces() async {
    final rows = await _db.query(
      tableName,
      where: 'label IS NOT NULL AND label != ?',
      whereArgs: [''],
    );
    return rows.map(FaceDetectionRecord.fromMap).toList();
  }

  /// Update the label for a specific face.
  Future<void> updateFaceLabel(String faceId, String label) async {
    await _db.update(
      tableName,
      {'label': label},
      where: 'id = ?',
      whereArgs: [faceId],
    );
  }

  /// Merge all faces with a source label into a target label.
  Future<void> mergeFaceLabels(String sourceLabel, String targetLabel) async {
    await _db.update(
      tableName,
      {'label': targetLabel},
      where: 'label = ?',
      whereArgs: [sourceLabel],
    );
  }

  /// Delete faces by photo ID.
  Future<void> deleteFacesByPhotoId(String photoId) async {
    await _db.delete(
      tableName,
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
  }
}