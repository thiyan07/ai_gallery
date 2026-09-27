import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/logging/app_logger.dart';
import '../../../domain/models/edit/edit_operation.dart';
import '../../../domain/models/edit/user_edit_preset.dart';

/// Manages user-created edit presets (save/load/delete/rename).
///
/// Persists presets as a JSON file in the app documents directory.
/// This avoids database schema changes and keeps presets portable.
class UserPresetService {
  UserPresetService({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;
  static const _fileName = 'user_edit_presets.json';
  static const _uuid = Uuid();
  List<UserEditPreset>? _cache;

  /// Get the presets file path.
  Future<File> _presetsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Load all presets from disk.
  Future<List<UserEditPreset>> loadAll() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _presetsFile();
      if (!await file.exists()) {
        _cache = [];
        return _cache!;
      }
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      _cache = list
          .map((e) => UserEditPreset.fromMap(e as Map<String, dynamic>))
          .toList();
      return _cache!;
    } catch (e, st) {
      _logger.error('Failed to load user presets', error: e, stackTrace: st);
      _cache = [];
      return _cache!;
    }
  }

  /// Save all presets to disk.
  Future<void> _saveAll(List<UserEditPreset> presets) async {
    final file = await _presetsFile();
    final json = jsonEncode(presets.map((p) => p.toMap()).toList());
    await file.writeAsString(json);
    _cache = presets;
  }

  /// Create a new preset. Returns the created preset.
  Future<UserEditPreset> create({
    required String name,
    required List<EditOperation> operations,
    String? thumbnailPhotoId,
  }) async {
    final presets = await loadAll();
    final now = DateTime.now();
    final preset = UserEditPreset(
      id: _uuid.v4(),
      name: name,
      operations: operations,
      createdAt: now,
      updatedAt: now,
      thumbnailPhotoId: thumbnailPhotoId,
    );
    presets.add(preset);
    await _saveAll(presets);
    _logger.info('Created user preset: ${preset.name} (${preset.id})');
    return preset;
  }

  /// Update an existing preset.
  Future<void> update(UserEditPreset updated) async {
    final presets = await loadAll();
    final idx = presets.indexWhere((p) => p.id == updated.id);
    if (idx < 0) return;
    presets[idx] = updated.copyWith(updatedAt: DateTime.now());
    await _saveAll(presets);
    _logger.info('Updated user preset: ${updated.name}');
  }

  /// Delete a preset by ID.
  Future<void> delete(String id) async {
    final presets = await loadAll();
    presets.removeWhere((p) => p.id == id);
    await _saveAll(presets);
    _logger.info('Deleted user preset: $id');
  }

  /// Get a preset by ID.
  Future<UserEditPreset?> getById(String id) async {
    final presets = await loadAll();
    try {
      return presets.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Rename a preset.
  Future<void> rename(String id, String newName) async {
    final presets = await loadAll();
    final idx = presets.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    presets[idx] = presets[idx].copyWith(
      name: newName,
      updatedAt: DateTime.now(),
    );
    await _saveAll(presets);
    _logger.info('Renamed user preset $id → $newName');
  }

  /// Clear the in-memory cache (call after external file changes).
  void invalidateCache() {
    _cache = null;
  }
}
