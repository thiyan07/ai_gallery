import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/logging/app_logger.dart';
import '../../../domain/models/edit/edit_operation.dart';
import '../../../domain/models/edit/edit_recipe.dart';

/// A versioned snapshot of an edit recipe.
class EditDocumentVersion {
  final String versionId;
  final String photoId;
  final List<EditOperation> operations;
  final DateTime createdAt;
  final String label;
  final int versionNumber;

  const EditDocumentVersion({
    required this.versionId,
    required this.photoId,
    required this.operations,
    required this.createdAt,
    this.label = '',
    required this.versionNumber,
  });

  Map<String, dynamic> toMap() => {
        'version_id': versionId,
        'photo_id': photoId,
        'operations': operations.map((op) => op.toMap()).toList(),
        'created_at': createdAt.toIso8601String(),
        'label': label,
        'version_number': versionNumber,
      };

  factory EditDocumentVersion.fromMap(Map<String, dynamic> map) =>
      EditDocumentVersion(
        versionId: map['version_id'] as String,
        photoId: map['photo_id'] as String,
        operations: (map['operations'] as List)
            .map((e) => EditOperation.fromMap(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(map['created_at'] as String),
        label: map['label'] as String? ?? '',
        versionNumber: map['version_number'] as int,
      );

  /// Build an EditRecipe from this version.
  EditRecipe toRecipe() => EditRecipe(
        photoId: photoId,
        operations: operations,
        createdAt: createdAt,
        updatedAt: createdAt,
        version: versionNumber,
      );

  String toJson() => jsonEncode(toMap());
  factory EditDocumentVersion.fromJson(String json) =>
      EditDocumentVersion.fromMap(jsonDecode(json) as Map<String, dynamic>);
}

/// Manages version history for a single photo's edit recipe.
///
/// Maintains a list of versioned snapshots. Each save creates a new version.
/// Versions can be listed, compared, and restored.
class EditDocumentVersioning {
  EditDocumentVersioning({
    required AppLogger logger,
  }) : _logger = logger;

  final AppLogger _logger;
  static const _uuid = Uuid();
  static const int maxVersions = 20;

  final Map<String, List<EditDocumentVersion>> _versions = {};

  /// Get all versions for a photo.
  List<EditDocumentVersion> getVersions(String photoId) {
    return List.unmodifiable(_versions[photoId] ?? []);
  }

  /// Get the latest version for a photo.
  EditDocumentVersion? getLatest(String photoId) {
    final versions = _versions[photoId];
    if (versions == null || versions.isEmpty) return null;
    return versions.last;
  }

  /// Save a new version of a recipe.
  EditDocumentVersion saveVersion(
    String photoId,
    EditRecipe recipe, {
    String label = '',
  }) {
    final existing = _versions[photoId] ?? [];
    final versionNumber = existing.length + 1;

    final version = EditDocumentVersion(
      versionId: _uuid.v4(),
      photoId: photoId,
      operations: List.from(recipe.operations),
      createdAt: DateTime.now(),
      label: label.isNotEmpty ? label : 'Version $versionNumber',
      versionNumber: versionNumber,
    );

    existing.add(version);

    // Enforce limit
    while (existing.length > maxVersions) {
      existing.removeAt(0);
    }

    _versions[photoId] = existing;
    _logger.info('Saved version $versionNumber for $photoId');
    return version;
  }

  /// Restore a specific version, creating a new version from it.
  EditRecipe? restoreVersion(String photoId, String versionId) {
    final versions = _versions[photoId];
    if (versions == null) return null;

    final version = versions.where((v) => v.versionId == versionId).firstOrNull;
    if (version == null) return null;

    // Create a new version from the restored one
    final restored = saveVersion(
      photoId,
      version.toRecipe(),
      label: 'Restored from v${version.versionNumber}',
    );

    _logger.info(
      'Restored version ${version.versionNumber} for $photoId',
    );
    return restored.toRecipe();
  }

  /// Compare two versions (returns operations that differ).
  Map<String, dynamic> compareVersions(
    String photoId,
    String versionIdA,
    String versionIdB,
  ) {
    final versions = _versions[photoId];
    if (versions == null) return {};

    final a = versions.where((v) => v.versionId == versionIdA).firstOrNull;
    final b = versions.where((v) => v.versionId == versionIdB).firstOrNull;
    if (a == null || b == null) return {};

    return {
      'a_label': a.label,
      'b_label': b.label,
      'a_operations': a.operations.length,
      'b_operations': b.operations.length,
      'a_created': a.createdAt.toIso8601String(),
      'b_created': b.createdAt.toIso8601String(),
    };
  }

  /// Delete all versions for a photo.
  void clearVersions(String photoId) {
    _versions.remove(photoId);
    _logger.info('Cleared versions for $photoId');
  }

  /// Serialize all versions for a photo as JSON.
  String toJson(String photoId) {
    final versions = _versions[photoId] ?? [];
    return jsonEncode(versions.map((v) => v.toMap()).toList());
  }

  /// Deserialize versions from JSON.
  void fromJson(String photoId, String json) {
    final list = jsonDecode(json) as List;
    _versions[photoId] = list
        .map((e) => EditDocumentVersion.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
