import 'package:photo_manager/photo_manager.dart';

import '../../../core/logging/app_logger.dart';
import '../../../domain/models/edit/edit_operation.dart';
import '../../../domain/models/edit/edit_recipe.dart';
import 'edit_export_service.dart';

/// Result of a batch edit operation on a single photo.
class BatchEditResult {
  final String photoId;
  final bool success;
  final String? error;
  final String? exportedPath;

  const BatchEditResult({
    required this.photoId,
    required this.success,
    this.error,
    this.exportedPath,
  });
}

/// Applies edit operations to multiple photos as a batch job.
///
/// Each photo is exported at full resolution using the same recipe.
/// Results are reported incrementally via [progressCallback].
class BatchEditService {
  BatchEditService({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  /// Apply a recipe (or specific operations from it) to multiple photos.
  ///
  /// [recipe] — the source recipe to apply.
  /// [photoIds] — target photos to apply the recipe to.
  /// [operationTypes] — if non-null, only these operation types are applied
  ///   (for "paste adjustments only" mode). If null, the full recipe is applied.
  /// [progressCallback] — called with (completed, total) after each photo.
  Future<List<BatchEditResult>> applyToPhotos({
    required EditRecipe recipe,
    required List<String> photoIds,
    List<EditOperationType>? operationTypes,
    void Function(int completed, int total)? progressCallback,
    EditCancelToken? cancelToken,
  }) async {
    final exportService = EditExportService(logger: _logger);
    final results = <BatchEditResult>[];

    // Build the operations to apply
    var opsToApply = recipe.operations.where((op) => !op.isNoOp).toList();
    if (operationTypes != null) {
      opsToApply =
          opsToApply.where((op) => operationTypes.contains(op.type)).toList();
    }

    final total = photoIds.length;
    for (var i = 0; i < total; i++) {
      if (cancelToken?.isCancelled == true) break;

      final photoId = photoIds[i];
      try {
        final photoRecipe = EditRecipe(
          photoId: photoId,
          operations: opsToApply,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final exportedPath = await exportService.exportPhoto(
          photoId: photoId,
          recipe: photoRecipe,
          cancelToken: cancelToken,
        );

        results.add(BatchEditResult(
          photoId: photoId,
          success: true,
          exportedPath: exportedPath,
        ));
      } catch (e) {
        _logger.warning('Batch edit failed for $photoId: $e');
        results.add(BatchEditResult(
          photoId: photoId,
          success: false,
          error: e.toString(),
        ));
      }

      progressCallback?.call(i + 1, total);
    }

    final succeeded = results.where((r) => r.success).length;
    _logger.info(
      'Batch edit complete: $succeeded/$total succeeded',
    );

    return results;
  }
}
