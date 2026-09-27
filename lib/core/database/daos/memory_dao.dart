import 'package:sqflite/sqflite.dart';

import '../../../domain/models/memory/memory.dart';
import '../../../domain/models/memory/automatic_album.dart';

/// DAO for memories and automatic albums.
class MemoryDao {
  MemoryDao(this._db);

  final Database _db;

  // --- Memories ---

  Future<void> insertMemory(Memory memory) async {
    await _db.insert('memories', memory.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertMemories(List<Memory> memories) async {
    final batch = _db.batch();
    for (final memory in memories) {
      batch.insert('memories', memory.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Memory?> getMemory(String memoryId) async {
    final rows = await _db.query('memories', where: 'memory_id = ?', whereArgs: [memoryId]);
    if (rows.isEmpty) return null;
    return Memory.fromMap(rows.first);
  }

  Future<List<Memory>> getAllMemories() async {
    final rows = await _db.query('memories', orderBy: 'score DESC');
    return rows.map(Memory.fromMap).toList();
  }

  Future<List<Memory>> getActiveMemories() async {
    final rows = await _db.query(
      'memories',
      where: 'status = ?',
      whereArgs: [MemoryStatus.active.index],
      orderBy: 'score DESC',
    );
    return rows.map(Memory.fromMap).toList();
  }

  Future<List<Memory>> getMemoriesByTheme(MemoryTheme theme) async {
    final rows = await _db.query(
      'memories',
      where: 'theme = ? AND status = ?',
      whereArgs: [theme.index, MemoryStatus.active.index],
      orderBy: 'score DESC',
    );
    return rows.map(Memory.fromMap).toList();
  }

  Future<List<Memory>> getMemoriesByDateRange(DateTime start, DateTime end) async {
    final rows = await _db.query(
      'memories',
      where: 'start_date >= ? AND end_date <= ? AND status = ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String(), MemoryStatus.active.index],
      orderBy: 'score DESC',
    );
    return rows.map(Memory.fromMap).toList();
  }

  Future<List<Memory>> getMemoriesByPerson(String personId) async {
    final rows = await _db.rawQuery('''
      SELECT * FROM memories
      WHERE person_ids LIKE ? AND status = ?
      ORDER BY score DESC
    ''', ['%$personId%', MemoryStatus.active.index]);
    return rows.map(Memory.fromMap).toList();
  }

  Future<void> updateMemoryStatus(String memoryId, MemoryStatus status) async {
    await _db.update(
      'memories',
      {
        'status': status.index,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'memory_id = ?',
      whereArgs: [memoryId],
    );
  }

  Future<void> updateMemory(String memoryId, Map<String, Object?> updates) async {
    updates['updated_at'] = DateTime.now().toIso8601String();
    await _db.update('memories', updates, where: 'memory_id = ?', whereArgs: [memoryId]);
  }

  Future<void> deleteMemory(String memoryId) async {
    await _db.delete('memories', where: 'memory_id = ?', whereArgs: [memoryId]);
  }

  Future<int> getMemoryCount() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as count FROM memories');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getActiveMemoryCount() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM memories WHERE status = ?',
      [MemoryStatus.active.index],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // --- Automatic Albums ---

  Future<void> insertAutomaticAlbum(AutomaticAlbum album) async {
    await _db.insert('automatic_albums', album.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertAutomaticAlbums(List<AutomaticAlbum> albums) async {
    final batch = _db.batch();
    for (final album in albums) {
      batch.insert('automatic_albums', album.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<AutomaticAlbum?> getAutomaticAlbum(String albumId) async {
    final rows = await _db.query('automatic_albums', where: 'album_id = ?', whereArgs: [albumId]);
    if (rows.isEmpty) return null;
    return AutomaticAlbum.fromMap(rows.first);
  }

  Future<List<AutomaticAlbum>> getAllAutomaticAlbums() async {
    final rows = await _db.query('automatic_albums', orderBy: 'score DESC');
    return rows.map(AutomaticAlbum.fromMap).toList();
  }

  Future<List<AutomaticAlbum>> getVisibleAutomaticAlbums() async {
    final rows = await _db.query(
      'automatic_albums',
      where: 'is_hidden = 0',
      orderBy: 'score DESC',
    );
    return rows.map(AutomaticAlbum.fromMap).toList();
  }

  Future<List<AutomaticAlbum>> getAutomaticAlbumsByType(AutomaticAlbumType type) async {
    final rows = await _db.query(
      'automatic_albums',
      where: 'type = ? AND is_hidden = 0',
      whereArgs: [type.index],
      orderBy: 'score DESC',
    );
    return rows.map(AutomaticAlbum.fromMap).toList();
  }

  Future<void> hideAutomaticAlbum(String albumId) async {
    await _db.update(
      'automatic_albums',
      {'is_hidden': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
  }

  Future<void> showAutomaticAlbum(String albumId) async {
    await _db.update(
      'automatic_albums',
      {'is_hidden': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
  }

  Future<void> deleteAutomaticAlbum(String albumId) async {
    await _db.delete('automatic_albums', where: 'album_id = ?', whereArgs: [albumId]);
  }

  // --- Batch operations ---

  Future<void> replaceAll(List<Memory> memories, List<AutomaticAlbum> albums) async {
    final batch = _db.batch();
    batch.delete('memories');
    batch.delete('automatic_albums');
    for (final memory in memories) {
      batch.insert('memories', memory.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final album in albums) {
      batch.insert('automatic_albums', album.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
