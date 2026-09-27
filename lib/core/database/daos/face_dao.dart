import 'dart:typed_data';

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

  /// Batch: get all faces for a set of photo IDs (avoids N+1).
  Future<Map<String, List<FaceDetectionRecord>>> getFacesByPhotoIds(
    Set<String> photoIds,
  ) async {
    if (photoIds.isEmpty) return {};
    final placeholders = List.filled(photoIds.length, '?').join(',');
    final rows = await _db.query(
      tableName,
      where: 'photo_id IN ($placeholders)',
      whereArgs: photoIds.toList(),
    );
    final map = <String, List<FaceDetectionRecord>>{};
    for (final row in rows) {
      final rec = FaceDetectionRecord.fromMap(row);
      (map[rec.photoId] ??= []).add(rec);
    }
    return map;
  }

  /// Get a face by its ID.
  Future<FaceDetectionRecord?> getFaceById(String faceId) async {
    final rows = await _db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [faceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FaceDetectionRecord.fromMap(rows.first);
  }

  /// Get faces by person ID.
  Future<List<FaceDetectionRecord>> getFacesByPersonId(String personId) async {
    final rows = await _db.query(
      tableName,
      where: 'person_id = ?',
      whereArgs: [personId],
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
      whereArgs: [Uint8List(0)],
      limit: limit,
      offset: offset,
    );
    return rows.map(FaceDetectionRecord.fromMap).toList();
  }

  /// Get all faces that have both a label and embedding (for clustering operations).
  Future<List<FaceDetectionRecord>> getLabelledFacesWithEmbeddings() async {
    final rows = await _db.query(
      tableName,
      where: 'label IS NOT NULL AND label != ? AND embedding IS NOT NULL AND embedding != ?',
      whereArgs: ['', Uint8List(0)],
    );
    return rows.map(FaceDetectionRecord.fromMap).toList();
  }

  /// Update all faces with a source label to have a target label.
  Future<void> updateFacesLabel(String sourceLabel, String targetLabel) async {
    await _db.update(
      tableName,
      {'label': targetLabel},
      where: 'label = ?',
      whereArgs: [sourceLabel],
    );
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

  /// Get all faces that are assigned to a person (have person_id).
  Future<List<FaceDetectionRecord>> getFacesWithPerson() async {
    final rows = await _db.query(
      tableName,
      where: 'person_id IS NOT NULL',
    );
    return rows.map(FaceDetectionRecord.fromMap).toList();
  }

  /// Get all faces assigned to a specific person.
  Future<List<FaceDetectionRecord>> getByPersonId(String personId) async {
    final rows = await _db.query(
      tableName,
      where: 'person_id = ?',
      whereArgs: [personId],
    );
    return rows.map(FaceDetectionRecord.fromMap).toList();
  }

  /// Get all faces that are unassigned (no person_id).
  Future<List<FaceDetectionRecord>> getUnassignedFaces() async {
    final rows = await _db.query(
      tableName,
      where: 'person_id IS NULL',
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

  /// Update the person ID for a specific face.
  Future<void> updateFacePerson(String faceId, String? personId) async {
    await _db.update(
      tableName,
      {'person_id': personId},
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

  /// Assign multiple faces to a person.
  Future<void> assignFacesToPerson(List<String> faceIds, String personId) async {
    final batch = _db.batch();
    for (final faceId in faceIds) {
      batch.update(
        tableName,
        {'person_id': personId},
        where: 'id = ?',
        whereArgs: [faceId],
      );
    }
    await batch.commit();
  }

  /// Remove person assignment from multiple faces.
  Future<void> removeFacesFromPerson(List<String> faceIds) async {
    final batch = _db.batch();
    for (final faceId in faceIds) {
      batch.update(
        tableName,
        {'person_id': null},
        where: 'id = ?',
        whereArgs: [faceId],
      );
    }
    await batch.commit();
  }

  /// Merge all faces with a source person into a target person.
  Future<void> mergePersons(String sourcePersonId, String targetPersonId) async {
    await _db.update(
      tableName,
      {'person_id': targetPersonId},
      where: 'person_id = ?',
      whereArgs: [sourcePersonId],
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