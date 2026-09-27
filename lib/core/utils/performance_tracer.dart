import 'dart:collection';

import '../logging/app_logger.dart';

/// Lightweight stage-based profiling utility.
///
/// Usage:
/// ```dart
/// final tracer = PerformanceTracer(logger: logger, enabled: true);
/// tracer.start('db_init');
/// await database.open();
/// tracer.end('db_init');
/// print(tracer.summary());
/// ```
///
/// Call [reset] between measurement runs. Call [disable]/[enable] at runtime.
class PerformanceTracer {
  PerformanceTracer({required AppLogger logger, bool enabled = true})
      : _logger = logger,
        _enabled = enabled;

  final AppLogger _logger;
  bool _enabled;

  final LinkedHashMap<String, _Stage> _stages = LinkedHashMap();

  bool get enabled => _enabled;
  void enable() => _enabled = true;
  void disable() => _enabled = false;

  /// Record a completed stage with [name] and [elapsed].
  void record(String name, Duration elapsed) {
    if (!_enabled) return;
    final existing = _stages[name];
    if (existing == null) {
      _stages[name] = _Stage(initialMicros: elapsed.inMicroseconds);
    } else {
      existing.accumulate(elapsed);
    }
  }

  /// Start timing a stage. Returns a [Stopwatch] you can optionally stop
  /// manually — or call [end] with the same [name].
  Stopwatch start(String name) {
    if (!_enabled) return Stopwatch();
    final sw = Stopwatch()..start();
    _stages[name] ??= _Stage();
    _stages[name]!._currentStopwatch = sw;
    return sw;
  }

  /// End timing a previously [start]ed stage and record its duration.
  Duration end(String name) {
    if (!_enabled) return Duration.zero;
    final stage = _stages[name];
    if (stage == null || stage._currentStopwatch == null) {
      return Duration.zero;
    }
    final sw = stage._currentStopwatch!;
    sw.stop();
    stage.accumulate(Duration(microseconds: sw.elapsedMicroseconds));
    stage._currentStopwatch = null;
    return Duration(microseconds: sw.elapsedMicroseconds);
  }

  /// Get all recorded stage names in insertion order.
  List<String> get stages => _stages.keys.toList();

  /// Get the average duration for a stage.
  Duration average(String name) {
    final stage = _stages[name];
    if (stage == null || stage.count == 0) return Duration.zero;
    return Duration(microseconds: (stage.totalMicros / stage.count).round());
  }

  /// Get total duration across all invocations of a stage.
  Duration total(String name) {
    final stage = _stages[name];
    if (stage == null) return Duration.zero;
    return Duration(microseconds: stage.totalMicros);
  }

  /// Get invocation count for a stage.
  int count(String name) => _stages[name]?.count ?? 0;

  /// Get min/max/avg for a stage.
  StageStats? stats(String name) {
    final stage = _stages[name];
    if (stage == null || stage.count == 0) return null;
    return StageStats(
      count: stage.count,
      avgMs: stage.totalMicros / stage.count / 1000.0,
      minMs: stage.minMicros / 1000.0,
      maxMs: stage.maxMicros / 1000.0,
      totalMs: stage.totalMicros / 1000.0,
    );
  }

  /// Return a human-readable summary of all stages.
  String summary() {
    final buf = StringBuffer();
    buf.writeln('=== Performance Summary ===');
    for (final entry in _stages.entries) {
      final s = entry.value;
      if (s.count == 0) continue;
      final avg = s.totalMicros / s.count / 1000.0;
      buf.writeln(
        '  ${entry.key.padRight(30)} '
        '${avg.toStringAsFixed(1).padLeft(10)} ms avg '
        '(${s.count}x, total ${(s.totalMicros / 1000.0).toStringAsFixed(1)} ms)',
      );
    }
    buf.writeln('===========================');
    return buf.toString();
  }

  /// Log the summary via the app logger.
  void logSummary() {
    _logger.info(summary());
  }

  /// Clear all recorded stages.
  void reset() {
    _stages.clear();
  }

  /// Export results as a flat map (for serialization / test assertions).
  Map<String, double> toMap() {
    final result = <String, double>{};
    for (final entry in _stages.entries) {
      final s = entry.value;
      if (s.count > 0) {
        result[entry.key] = s.totalMicros / 1000.0;
      }
    }
    return result;
  }
}

class _Stage {
  _Stage({int? initialMicros}) {
    if (initialMicros != null) {
      totalMicros = initialMicros;
      minMicros = initialMicros;
      maxMicros = initialMicros;
      count = 1;
    }
  }

  int totalMicros = 0;
  int minMicros = 9223372036854775807; // max int
  int maxMicros = 0;
  int count = 0;
  Stopwatch? _currentStopwatch;

  void accumulate(Duration elapsed) {
    final us = elapsed.inMicroseconds;
    totalMicros += us;
    if (us < minMicros) minMicros = us;
    if (us > maxMicros) maxMicros = us;
    count++;
  }
}

/// Aggregated stats for a single stage.
class StageStats {
  const StageStats({
    required this.count,
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.totalMs,
  });

  final int count;
  final double avgMs;
  final double minMs;
  final double maxMs;
  final double totalMs;

  @override
  String toString() =>
      '${count}x avg=${avgMs.toStringAsFixed(1)}ms '
      'min=${minMs.toStringAsFixed(1)}ms max=${maxMs.toStringAsFixed(1)}ms '
      'total=${totalMs.toStringAsFixed(1)}ms';
}
