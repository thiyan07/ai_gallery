import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/logging/app_logger.dart';
import '../../../domain/models/edit/edit_recipe.dart';
import 'edit_transformation_engine.dart';

/// Simple cancellation token for export operations.
class EditCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Handles atomic export of edited photos to a dedicated directory.
///
/// Export flow:
/// 1. Load full-resolution original via AssetEntity.originFile
/// 2. Apply edit recipe at full resolution
/// 3. Write to temp file (<photoId>.jpg.tmp)
/// 4. Rename temp → final (<photoId>.jpg) — atomic on same filesystem
/// 5. Return exported path
///
/// Originals are never modified.
class EditExportService {
  EditExportService({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  Directory? _editedDir;

  /// Ensure the edited-images directory exists.
  Future<Directory> ensureEditedDirectory() async {
    if (_editedDir != null && await _editedDir!.exists()) return _editedDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _editedDir = Directory(p.join(appDir.path, 'edited'));
    if (!await _editedDir!.exists()) {
      await _editedDir!.create(recursive: true);
      _logger.info('Created edited directory: ${_editedDir!.path}');
    }
    return _editedDir!;
  }

  /// Export an edited photo at full resolution.
  ///
  /// Returns the final exported file path.
  /// Throws on failure; temp files are cleaned up automatically.
  Future<String> exportPhoto({
    required String photoId,
    required EditRecipe recipe,
    void Function(double)? progressCallback,
    EditCancelToken? cancelToken,
  }) async {
    final editedDir = await ensureEditedDirectory();
    final tempPath = p.join(editedDir.path, '$photoId.jpg.tmp');
    final finalPath = p.join(editedDir.path, '$photoId.jpg');
    File? tempFile;

    try {
      // Load original
      progressCallback?.call(0.0);

      final asset = await AssetEntity.fromId(photoId);
      if (asset == null) {
        throw StateError('Photo not found: $photoId');
      }

      if (cancelToken?.isCancelled == true) {
        throw StateError('Export cancelled');
      }

      final originFile = await asset.originFile;
      if (originFile == null) {
        throw StateError('Could not load photo file: $photoId');
      }

      final bytes = await originFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw StateError('Could not decode photo: $photoId');
      }

      if (cancelToken?.isCancelled == true) {
        throw StateError('Export cancelled');
      }

      // Apply edits at full resolution
      progressCallback?.call(0.3);

      final result = EditTransformationEngine.applyAndEncode(
        decoded,
        recipe,
        quality: 95,
      );

      if (cancelToken?.isCancelled == true) {
        throw StateError('Export cancelled');
      }

      // Write to temp file
      progressCallback?.call(0.7);

      tempFile = File(tempPath);
      await tempFile.writeAsBytes(result, flush: true);

      if (cancelToken?.isCancelled == true) {
        throw StateError('Export cancelled');
      }

      // Atomic rename temp → final
      progressCallback?.call(0.9);

      await tempFile.rename(finalPath);

      _logger.info('Exported edited photo: $photoId → $finalPath '
          '(${result.length} bytes)');

      progressCallback?.call(1.0);

      return finalPath;
    } catch (e) {
      // Clean up temp file on failure
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Delete the exported file for a photo.
  Future<void> deleteExport(String photoId) async {
    final path = await getExportPath(photoId);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        _logger.info('Deleted exported file: $path');
      }
    }
  }

  /// Return the export path if the file exists, null otherwise.
  Future<String?> getExportPath(String photoId) async {
    final editedDir = await ensureEditedDirectory();
    final path = p.join(editedDir.path, '$photoId.jpg');
    if (await File(path).exists()) return path;
    return null;
  }

  /// Check if an exported file exists for a photo.
  Future<bool> hasExport(String photoId) async {
    return (await getExportPath(photoId)) != null;
  }
}
