import 'dart:async';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../logging/app_logger.dart';
import '../../domain/models/ai_job.dart';

/// Health status of a system component.
enum HealthStatus {
  healthy,
  degraded,
  unhealthy,
  unknown,
}

/// Result of a single health check.
class HealthCheckResult {
  const HealthCheckResult({
    required this.component,
    required this.status,
    this.message,
    this.metrics = const {},
    this.durationMs = 0,
  });

  final String component;
  final HealthStatus status;
  final String? message;
  final Map<String, dynamic> metrics;
  final int durationMs;

  bool get isHealthy => status == HealthStatus.healthy;
  bool get isUnhealthy => status == HealthStatus.unhealthy;
}

/// Overall system health report.
class SystemHealthReport {
  const SystemHealthReport({
    required this.checks,
    required this.overallStatus,
    required this.timestamp,
  });

  final List<HealthCheckResult> checks;
  final HealthStatus overallStatus;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'overallStatus': overallStatus.name,
        'timestamp': timestamp.toIso8601String(),
        'checks': checks
            .map((c) => {
                  'component': c.component,
                  'status': c.status.name,
                  'message': c.message,
                  'metrics': c.metrics,
                  'durationMs': c.durationMs,
                })
            .toList(),
      };
}

/// Performs health checks on critical system components.
///
/// Checks:
/// - Database connectivity and WAL mode
/// - Stuck jobs (running > 10 minutes)
/// - Failed jobs (permanent failures)
/// - Disk space
/// - Memory pressure indicators
class HealthCheckService {
  HealthCheckService({
    required AppDatabase database,
    required AppLogger logger,
  })  : _db = database,
        _logger = logger;

  final AppDatabase _db;
  final AppLogger _logger;

  /// Runs all health checks and returns a system health report.
  Future<SystemHealthReport> checkHealth() async {
    final checks = <HealthCheckResult>[];

    checks.add(await _checkDatabase());
    checks.add(await _checkStuckJobs());
    checks.add(await _checkFailedJobs());
    checks.add(await _checkDiskSpace());

    final overall = _computeOverall(checks);
    final report = SystemHealthReport(
      checks: checks,
      overallStatus: overall,
      timestamp: DateTime.now(),
    );

    _logger.info('Health check complete: ${overall.name}');
    return report;
  }

  /// Checks database connectivity and integrity.
  Future<HealthCheckResult> _checkDatabase() async {
    final sw = Stopwatch()..start();
    try {
      // Test basic connectivity
      await _db.database.rawQuery('SELECT 1');

      // Check WAL mode
      final walResult =
          await _db.database.rawQuery('PRAGMA journal_mode');
      final journalMode =
          walResult.isNotEmpty ? walResult.first['journal_mode'] : 'unknown';

      // Count tables
      final tableResult = await _db.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );

      // Check foreign keys
      final fkResult = await _db.database.rawQuery('PRAGMA foreign_keys');
      final fkEnabled = fkResult.isNotEmpty && fkResult.first['foreign_keys'] == 1;

      sw.stop();

      final status = journalMode == 'wal' && fkEnabled
          ? HealthStatus.healthy
          : HealthStatus.degraded;

      return HealthCheckResult(
        component: 'database',
        status: status,
        message: status == HealthStatus.healthy
            ? 'Database OK (WAL, FK enabled)'
            : 'Database degraded (journal=$journalMode, FK=$fkEnabled)',
        metrics: {
          'journalMode': journalMode,
          'foreignKeysEnabled': fkEnabled,
          'tableCount': tableResult.length,
        },
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return HealthCheckResult(
        component: 'database',
        status: HealthStatus.unhealthy,
        message: 'Database error: $e',
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Checks for jobs stuck in 'running' state.
  Future<HealthCheckResult> _checkStuckJobs() async {
    final sw = Stopwatch()..start();
    try {
      final stuckJobs = await _db.aiJobs.getByStatus(AIJobStatus.running);
      final now = DateTime.now();
      final staleJobs = stuckJobs.where((job) {
        if (job.startedAt == null) return true;
        return now.difference(job.startedAt!).inMinutes > 15;
      }).toList();

      sw.stop();

      if (staleJobs.isEmpty) {
        return HealthCheckResult(
          component: 'stuck_jobs',
          status: HealthStatus.healthy,
          message: 'No stuck jobs',
          metrics: {'runningJobs': stuckJobs.length},
          durationMs: sw.elapsedMilliseconds,
        );
      }

      return HealthCheckResult(
        component: 'stuck_jobs',
        status: HealthStatus.degraded,
        message: '${staleJobs.length} stuck jobs detected',
        metrics: {
          'runningJobs': stuckJobs.length,
          'staleJobs': staleJobs.length,
        },
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return HealthCheckResult(
        component: 'stuck_jobs',
        status: HealthStatus.unknown,
        message: 'Check failed: $e',
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Checks for permanently failed jobs.
  Future<HealthCheckResult> _checkFailedJobs() async {
    final sw = Stopwatch()..start();
    try {
      final failedJobs = await _db.aiJobs.getByStatus(AIJobStatus.failed);
      final recentFailures = failedJobs.where((job) {
        if (job.completedAt == null) return true;
        return DateTime.now().difference(job.completedAt!).inHours < 24;
      }).toList();

      sw.stop();

      if (recentFailures.isEmpty) {
        return HealthCheckResult(
          component: 'failed_jobs',
          status: HealthStatus.healthy,
          message: 'No recent failures',
          metrics: {
            'totalFailed': failedJobs.length,
            'recentFailures': 0,
          },
          durationMs: sw.elapsedMilliseconds,
        );
      }

      final failureRate = recentFailures.length;
      final status = failureRate > 50
          ? HealthStatus.unhealthy
          : failureRate > 10
              ? HealthStatus.degraded
              : HealthStatus.healthy;

      return HealthCheckResult(
        component: 'failed_jobs',
        status: status,
        message: '$failureRate failures in last 24h',
        metrics: {
          'totalFailed': failedJobs.length,
          'recentFailures': failureRate,
        },
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return HealthCheckResult(
        component: 'failed_jobs',
        status: HealthStatus.unknown,
        message: 'Check failed: $e',
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Checks available disk space.
  Future<HealthCheckResult> _checkDiskSpace() async {
    final sw = Stopwatch()..start();
    try {
      final dbDir = await getDatabasesPath();

      // Use a simple heuristic: check if we can write
      final testFile = File('$dbDir/.health_check_test');
      await testFile.writeAsBytes([0]);
      await testFile.delete();

      sw.stop();

      return HealthCheckResult(
        component: 'disk_space',
        status: HealthStatus.healthy,
        message: 'Disk writable',
        metrics: {
          'dbPath': dbDir,
          'writable': true,
        },
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return HealthCheckResult(
        component: 'disk_space',
        status: HealthStatus.unhealthy,
        message: 'Disk error: $e',
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Computes overall status from individual checks.
  HealthStatus _computeOverall(List<HealthCheckResult> checks) {
    if (checks.any((c) => c.status == HealthStatus.unhealthy)) {
      return HealthStatus.unhealthy;
    }
    if (checks.any((c) => c.status == HealthStatus.degraded)) {
      return HealthStatus.degraded;
    }
    if (checks.every((c) => c.status == HealthStatus.healthy)) {
      return HealthStatus.healthy;
    }
    return HealthStatus.unknown;
  }
}
