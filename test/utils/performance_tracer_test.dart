import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/utils/performance_tracer.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestLogger implements AppLogger {
  final messages = <String>[];
  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      messages.add(message);
  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      messages.add(message);
  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      messages.add(message);
  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      messages.add(message);
}

void main() {
  group('PerformanceTracer', () {
    late PerformanceTracer tracer;
    late _TestLogger logger;

    setUp(() {
      logger = _TestLogger();
      tracer = PerformanceTracer(logger: logger, enabled: true);
    });

    test('record stores elapsed time', () {
      tracer.record('test', Duration(milliseconds: 100));
      expect(tracer.total('test'), Duration(milliseconds: 100));
      expect(tracer.count('test'), 1);
    });

    test('record accumulates across multiple calls', () {
      tracer.record('test', Duration(milliseconds: 100));
      tracer.record('test', Duration(milliseconds: 200));
      expect(tracer.total('test'), Duration(milliseconds: 300));
      expect(tracer.count('test'), 2);
      expect(tracer.average('test'), Duration(milliseconds: 150));
    });

    test('start/end records duration', () async {
      tracer.start('stage');
      await Future.delayed(const Duration(milliseconds: 50));
      final elapsed = tracer.end('stage');
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(40));
      expect(tracer.count('stage'), 1);
    });

    test('disabled tracer discards all data', () {
      tracer.disable();
      tracer.record('test', Duration(milliseconds: 100));
      expect(tracer.count('test'), 0);
      expect(tracer.total('test'), Duration.zero);
    });

    test('stats returns correct min/max/avg', () {
      tracer.record('test', Duration(milliseconds: 100));
      tracer.record('test', Duration(milliseconds: 50));
      tracer.record('test', Duration(milliseconds: 200));
      final s = tracer.stats('test');
      expect(s, isNotNull);
      expect(s!.count, 3);
      expect(s.minMs, closeTo(50, 1));
      expect(s.maxMs, closeTo(200, 1));
      expect(s.avgMs, closeTo(116.67, 1));
    });

    test('summary includes all stages', () {
      tracer.record('alpha', Duration(milliseconds: 10));
      tracer.record('beta', Duration(milliseconds: 20));
      final s = tracer.summary();
      expect(s, contains('alpha'));
      expect(s, contains('beta'));
    });

    test('toMap returns correct values', () {
      tracer.record('x', Duration(milliseconds: 42));
      final m = tracer.toMap();
      expect(m['x'], closeTo(42, 1));
    });

    test('reset clears all data', () {
      tracer.record('test', Duration(milliseconds: 100));
      tracer.reset();
      expect(tracer.count('test'), 0);
    });

    test('enable/disable toggle works', () {
      tracer.record('a', Duration(milliseconds: 10));
      tracer.disable();
      tracer.record('b', Duration(milliseconds: 20));
      tracer.enable();
      tracer.record('c', Duration(milliseconds: 30));
      expect(tracer.count('a'), 1);
      expect(tracer.count('b'), 0);
      expect(tracer.count('c'), 1);
    });
  });
}
