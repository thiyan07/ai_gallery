import 'package:ai_gallery/core/logging/app_logger.dart';
import 'performance_tracer.dart';

/// App-wide performance tracker singleton.
///
/// Usage:
/// ```dart
/// PerformanceTracker.instance.start('startup');
/// // ... work ...
/// PerformanceTracker.instance.end('startup');
/// ```
class PerformanceTracker {
  PerformanceTracker._();
  static final instance = PerformanceTracker._();

  PerformanceTracer? _tracer;

  /// Initialize with a logger. Safe to call multiple times — resets state.
  void init(AppLogger logger, {bool enabled = true}) {
    _tracer = PerformanceTracer(logger: logger, enabled: enabled);
  }

  PerformanceTracer get _t {
    if (_tracer == null) {
      _tracer = PerformanceTracer(
        logger: const _NoOpLogger(),
        enabled: false,
      );
    }
    return _tracer!;
  }

  bool get enabled => _t.enabled;
  void enable() => _t.enable();
  void disable() => _t.disable();

  void record(String name, Duration elapsed) => _t.record(name, elapsed);
  Stopwatch start(String name) => _t.start(name);
  Duration end(String name) => _t.end(name);
  String summary() => _t.summary();
  void logSummary() => _t.logSummary();
  void reset() => _t.reset();
  Map<String, double> toMap() => _t.toMap();
  StageStats? stats(String name) => _t.stats(name);
}

class _NoOpLogger implements AppLogger {
  const _NoOpLogger();
  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) {}
  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) {}
  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) {}
  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}
}
