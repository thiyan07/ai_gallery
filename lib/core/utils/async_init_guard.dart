import 'dart:async';

/// A thread-safe initialization guard for async one-shot initialization.
///
/// Prevents concurrent calls to the same async initialization logic.
/// If multiple callers call [run] concurrently, only the first actually
/// executes the initializer; the others await the same result.
///
/// Usage:
/// ```dart
/// final _guard = AsyncInitGuard();
/// Future<void> ensureInitialized() => _guard.run(() => _doInit());
/// ```
class AsyncInitGuard {
  Completer<void>? _completer;

  /// Whether initialization has completed successfully.
  bool get isInitialized => _completer != null && _completer!.isCompleted;

  /// Whether initialization is currently in progress.
  bool get isInitializing => _completer != null && !_completer!.isCompleted;

  /// Run the initializer exactly once. Subsequent calls return immediately.
  Future<void> run(Future<void> Function() initializer) {
    if (_completer != null && _completer!.isCompleted) {
      return Future.value();
    }

    if (_completer != null && !_completer!.isCompleted) {
      return _completer!.future;
    }

    _completer = Completer<void>();
    initializer().then((_) {
      if (!_completer!.isCompleted) {
        _completer!.complete();
      }
    }).catchError((Object e, StackTrace st) {
      if (!_completer!.isCompleted) {
        _completer!.completeError(e, st);
      }
      _completer = null;
    });

    return _completer!.future;
  }

  /// Reset the guard, allowing re-initialization.
  void reset() {
    _completer = null;
  }
}
