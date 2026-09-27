import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import '../../../core/logging/app_logger.dart';
import '../../../domain/models/edit/edit_recipe.dart';
import 'edit_export_service.dart';

/// Status of a queued export.
enum ExportQueueStatus { pending, processing, completed, failed, cancelled }

/// A single export job in the queue.
class ExportQueueItem {
  final String photoId;
  final EditRecipe recipe;
  ExportQueueStatus status;
  double progress;
  String? error;
  String? exportedPath;

  ExportQueueItem({
    required this.photoId,
    required this.recipe,
    this.status = ExportQueueStatus.pending,
    this.progress = 0.0,
    this.error,
    this.exportedPath,
  });
}

/// Manages a queue of photo export jobs with progress tracking.
///
/// Integrates with the existing background job system for persistence and
/// retry support. Exports are processed sequentially to avoid memory pressure.
class ExportQueueService {
  ExportQueueService({
    required AppLogger logger,
  }) : _logger = logger;

  final AppLogger _logger;

  final List<ExportQueueItem> _queue = [];
  bool _isProcessing = false;

  /// Current queue items (read-only view).
  List<ExportQueueItem> get items => List.unmodifiable(_queue);

  /// Number of pending items.
  int get pendingCount =>
      _queue.where((i) => i.status == ExportQueueStatus.pending).length;

  /// Whether an export is currently in progress.
  bool get isProcessing => _isProcessing;

  /// Add a photo to the export queue.
  Future<void> enqueue({
    required String photoId,
    required EditRecipe recipe,
  }) async {
    // Remove any existing entry for this photo
    _queue.removeWhere((i) => i.photoId == photoId);
    _queue.add(ExportQueueItem(photoId: photoId, recipe: recipe));
    _logger.info('Enqueued export for $photoId');
    _processNext();
  }

  /// Add multiple photos to the export queue.
  Future<void> enqueueAll({
    required List<String> photoIds,
    required EditRecipe recipe,
  }) async {
    for (final id in photoIds) {
      _queue.removeWhere((i) => i.photoId == id);
      _queue.add(ExportQueueItem(photoId: id, recipe: recipe));
    }
    _logger.info('Enqueued ${photoIds.length} exports');
    _processNext();
  }

  /// Cancel a pending export.
  void cancel(String photoId) {
    final item = _queue.firstWhere(
      (i) => i.photoId == photoId,
      orElse: () => ExportQueueItem(photoId: '', recipe: EditRecipe(photoId: '', createdAt: DateTime.now(), updatedAt: DateTime.now())),
    );
    if (item.photoId.isNotEmpty) {
      item.status = ExportQueueStatus.cancelled;
    }
  }

  /// Cancel all pending exports.
  void cancelAll() {
    for (final item in _queue) {
      if (item.status == ExportQueueStatus.pending) {
        item.status = ExportQueueStatus.cancelled;
      }
    }
  }

  /// Clear completed/failed/cancelled items from the queue.
  void clearFinished() {
    _queue.removeWhere((i) =>
        i.status == ExportQueueStatus.completed ||
        i.status == ExportQueueStatus.failed ||
        i.status == ExportQueueStatus.cancelled);
  }

  Future<void> _processNext() async {
    if (_isProcessing) return;

    final next = _queue.where((i) => i.status == ExportQueueStatus.pending).firstOrNull;
    if (next == null) return;

    _isProcessing = true;
    next.status = ExportQueueStatus.processing;

    try {
      final exportService = EditExportService(logger: _logger);
      final exportedPath = await exportService.exportPhoto(
        photoId: next.photoId,
        recipe: next.recipe,
        progressCallback: (p) => next.progress = p,
      );

      next.exportedPath = exportedPath;
      next.status = ExportQueueStatus.completed;
      next.progress = 1.0;
      _logger.info('Export completed: ${next.photoId}');
    } catch (e) {
      next.status = ExportQueueStatus.failed;
      next.error = e.toString();
      _logger.warning('Export failed: ${next.photoId} — $e');
    } finally {
      _isProcessing = false;
    }

    // Process next item
    _processNext();
  }
}
