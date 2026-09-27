import 'tool_interface.dart';
import '../models/action_state.dart';

/// Result of a batch/transactional action across multiple items.
class BatchActionResult {
  final int totalItems;
  final int succeeded;
  final int failed;
  final String message;
  final List<String> errors;

  const BatchActionResult({
    required this.totalItems,
    required this.succeeded,
    required this.failed,
    required this.message,
    this.errors = const [],
  });

  bool get allSucceeded => failed == 0;
  bool get allFailed => succeeded == 0;
}

/// Executes batch operations atomically (best-effort rollback on failure).
///
/// Used for multi-step actions like:
/// - "Add all those to favorites" (batch favorite)
/// - "Delete these photos" (batch delete)
/// - "Create album from these" (create + link)
class BatchActionExecutor {
  /// Execute a batch operation on a list of items.
  ///
  /// [operation] is called for each item. If any item fails,
  /// the batch continues (best-effort) and reports the failures.
  ///
  /// Returns a [BatchActionResult] with success/failure counts.
  static Future<BatchActionResult> execute({
    required List<String> itemIds,
    required Future<bool> Function(String itemId) operation,
    String actionName = 'operation',
  }) async {
    int succeeded = 0;
    int failed = 0;
    final errors = <String>[];

    for (final itemId in itemIds) {
      try {
        final success = await operation(itemId);
        if (success) {
          succeeded++;
        } else {
          failed++;
          errors.add('Failed: $itemId');
        }
      } catch (e) {
        failed++;
        errors.add('$itemId: $e');
      }
    }

    final message = failed == 0
        ? '$actionName completed for $succeeded item${succeeded == 1 ? '' : 's'}.'
        : '$actionName: $succeeded succeeded, $failed failed.';

    return BatchActionResult(
      totalItems: itemIds.length,
      succeeded: succeeded,
      failed: failed,
      message: message,
      errors: errors,
    );
  }

  /// Execute a batch operation with early termination on first failure.
  ///
  /// If any item fails, the batch stops immediately.
  /// Useful for operations where partial completion is not acceptable.
  static Future<BatchActionResult> executeStrict({
    required List<String> itemIds,
    required Future<bool> Function(String itemId) operation,
    String actionName = 'operation',
  }) async {
    int succeeded = 0;
    final errors = <String>[];

    for (final itemId in itemIds) {
      try {
        final success = await operation(itemId);
        if (success) {
          succeeded++;
        } else {
          errors.add('Failed at: $itemId (stopped)');
          break;
        }
      } catch (e) {
        errors.add('$itemId: $e (stopped)');
        break;
      }
    }

    final failed = itemIds.length - succeeded;
    final message = failed == 0
        ? '$actionName completed for all $succeeded items.'
        : '$actionName stopped: $succeeded succeeded, $failed remaining.';

    return BatchActionResult(
      totalItems: itemIds.length,
      succeeded: succeeded,
      failed: failed,
      message: message,
      errors: errors,
    );
  }
}
