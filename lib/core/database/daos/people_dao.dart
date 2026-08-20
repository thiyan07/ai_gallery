import 'package:sqflite/sqflite.dart';

import '../../../domain/models/person.dart';

/// Data access object for the people table.
class PeopleDao {
  const PeopleDao(this._db);

  final Database _db;

  /// Inserts or replaces a person.
  Future<void> upsert(Person person) async {
    await _db.insert(
      'people',
      person.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns a person by ID, or null if not found.
  Future<Person?> getById(String personId) async {
    final rows = await _db.query(
      'people',
      where: 'person_id = ?',
      whereArgs: [personId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Person.fromMap(rows.first);
  }

  /// Returns all active people.
  Future<List<Person>> getAllActive() async {
    final rows = await _db.query(
      'people',
      where: 'status = ?',
      whereArgs: [PersonStatus.active.toValue()],
      orderBy: 'display_name COLLATE NOCASE ASC',
    );
    return rows.map(Person.fromMap).toList();
  }

  /// Returns all people (including merged/deleted for historical purposes).
  Future<List<Person>> getAll() async {
    final rows = await _db.query(
      'people',
      orderBy: 'display_name COLLATE NOCASE ASC',
    );
    return rows.map(Person.fromMap).toList();
  }

  /// Returns unknown people (those with null display_name).
  Future<List<Person>> getUnknownPeople() async {
    final rows = await _db.query(
      'people',
      where: 'display_name IS NULL AND status = ?',
      whereArgs: [PersonStatus.active.toValue()],
    );
    return rows.map(Person.fromMap).toList();
  }

  /// Returns known people (those with non-null display_name).
  Future<List<Person>> getKnownPeople() async {
    final rows = await _db.query(
      'people',
      where: 'display_name IS NOT NULL AND status = ?',
      whereArgs: [PersonStatus.active.toValue()],
      orderBy: 'display_name COLLATE NOCASE ASC',
    );
    return rows.map(Person.fromMap).toList();
  }

  /// Updates the display name of a person.
  Future<void> updateDisplayName(String personId, String? displayName) async {
    await _db.update(
      'people',
      {
        'display_name': displayName,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'person_id = ?',
      whereArgs: [personId],
    );
  }

  /// Updates the cover photo of a person.
  Future<void> updateCoverPhoto(String personId, String? photoId) async {
    await _db.update(
      'people',
      {
        'cover_photo_id': photoId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'person_id = ?',
      whereArgs: [personId],
    );
  }

  /// Marks a person as merged into another person.
  Future<void> markAsMerged(String personId) async {
    await _db.update(
      'people',
      {
        'status': PersonStatus.merged.toValue(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'person_id = ?',
      whereArgs: [personId],
    );
  }

  /// Marks a person as deleted.
  Future<void> markAsDeleted(String personId) async {
    await _db.update(
      'people',
      {
        'status': PersonStatus.deleted.toValue(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'person_id = ?',
      whereArgs: [personId],
    );
  }

  /// Reactivates a merged or deleted person.
  Future<void> reactivate(String personId) async {
    await _db.update(
      'people',
      {
        'status': PersonStatus.active.toValue(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'person_id = ?',
      whereArgs: [personId],
    );
  }

  /// Gets the count of people by status.
  Future<Map<PersonStatus, int>> getCountByStatus() async {
    final result = <PersonStatus, int>{};
    for (final status in PersonStatus.values) {
      final rows = await _db.query(
        'people',
        where: 'status = ?',
        whereArgs: [status.toValue()],
      );
      result[status] = rows.length;
    }
    return result;
  }

  /// Searches for people by display name (case-insensitive substring match).
  Future<List<Person>> searchByName(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final rows = await _db.query(
      'people',
      where: "display_name LIKE ? AND status = ?",
      whereArgs: ['%$trimmed%', PersonStatus.active.toValue()],
      orderBy: 'display_name COLLATE NOCASE ASC',
      limit: 20,
    );
    return rows.map(Person.fromMap).toList();
  }

  /// Gets a person by exact display name (case-insensitive).
  Future<Person?> getByDisplayName(String name) async {
    final rows = await _db.query(
      'people',
      where: 'LOWER(display_name) = LOWER(?) AND status = ?',
      whereArgs: [name.trim(), PersonStatus.active.toValue()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Person.fromMap(rows.first);
  }
}