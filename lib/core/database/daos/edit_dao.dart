import 'package:sqflite/sqflite.dart';

import '../../../domain/models/edit/edit_recipe.dart';

/// DAO for the edit_recipes table.
///
/// Stores non-destructive edit recipes as JSON. The operations column holds
/// the serialized edit pipeline. The photo_id is the AssetEntity.id.
class EditDao {
  const EditDao(this._db);

  final Database _db;

  /// Save or update an edit recipe for a photo.
  Future<void> upsert(EditRecipe recipe) async {
    await _db.insert(
      'edit_recipes',
      {
        'photo_id': recipe.photoId,
        'operations_json': recipe.operationsToJson(),
        'created_at': recipe.createdAt.toIso8601String(),
        'updated_at': recipe.updatedAt.toIso8601String(),
        'version': recipe.version,
        'is_exported': recipe.isExported ? 1 : 0,
        'exported_path': recipe.exportedPath,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get the edit recipe for a photo, or null if none exists.
  Future<EditRecipe?> getByPhotoId(String photoId) async {
    final rows = await _db.query(
      'edit_recipes',
      where: 'photo_id = ?',
      whereArgs: [photoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return EditRecipe.fromMap(
      row,
      operationsJson: row['operations_json'] as String?,
    );
  }

  /// Get all edit recipes (for sync/audit purposes).
  Future<List<EditRecipe>> getAll() async {
    final rows = await _db.query('edit_recipes', orderBy: 'updated_at DESC');
    return rows
        .map((r) => EditRecipe.fromMap(r, operationsJson: r['operations_json'] as String?))
        .toList();
  }

  /// Get all photo IDs that have edit recipes.
  Future<Set<String>> getAllEditedPhotoIds() async {
    final rows = await _db.query('edit_recipes', columns: ['photo_id']);
    return rows.map((r) => r['photo_id'] as String).toSet();
  }

  /// Get all exported edit recipes (photos with saved edited files).
  Future<List<EditRecipe>> getExported() async {
    final rows = await _db.query(
      'edit_recipes',
      where: 'is_exported = 1',
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((r) => EditRecipe.fromMap(r, operationsJson: r['operations_json'] as String?))
        .toList();
  }

  /// Update the export status of a recipe.
  Future<void> updateExport({
    required String photoId,
    required bool isExported,
    String? exportedPath,
  }) async {
    await _db.update(
      'edit_recipes',
      {
        'is_exported': isExported ? 1 : 0,
        'exported_path': exportedPath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
  }

  /// Delete an edit recipe (reverts photo to original).
  Future<void> deleteByPhotoId(String photoId) async {
    await _db.delete(
      'edit_recipes',
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
  }

  /// Check if a photo has an edit recipe.
  Future<bool> hasRecipe(String photoId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as cnt FROM edit_recipes WHERE photo_id = ?',
      [photoId],
    );
    return (result.first['cnt'] as int) > 0;
  }

  /// Count of all edit recipes.
  Future<int> count() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as cnt FROM edit_recipes');
    return result.first['cnt'] as int;
  }
}
