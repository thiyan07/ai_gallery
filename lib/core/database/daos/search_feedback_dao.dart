import 'package:sqflite/sqflite.dart';

/// DAO for search relevance feedback ("not relevant" hides).
///
/// Queries are normalized (lowercase, trimmed, collapsed whitespace) before
/// storage so "Beach  sunset" and "beach sunset" share feedback.
class SearchFeedbackDao {
  SearchFeedbackDao(this._db);

  final Database _db;

  static const String tableName = 'search_feedback';

  /// Normalize a query for feedback matching.
  static String normalizeQuery(String query) =>
      query.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Record that [photoId] is not relevant for [query].
  Future<void> markNotRelevant(String photoId, String query) async {
    final normalized = normalizeQuery(query);
    if (normalized.isEmpty) return;
    await _db.insert(
      tableName,
      {
        'photo_id': photoId,
        'query': normalized,
        'liked': 0,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Remove a "not relevant" mark (undo).
  Future<void> clearMark(String photoId, String query) async {
    await _db.delete(
      tableName,
      where: 'photo_id = ? AND query = ?',
      whereArgs: [photoId, normalizeQuery(query)],
    );
  }

  /// Photo IDs marked not-relevant for [query].
  Future<Set<String>> dislikedForQuery(String query) async {
    final normalized = normalizeQuery(query);
    if (normalized.isEmpty) return {};
    final rows = await _db.query(
      tableName,
      columns: ['photo_id'],
      where: 'query = ? AND liked = 0',
      whereArgs: [normalized],
    );
    return rows.map((r) => r['photo_id'] as String).toSet();
  }
}
