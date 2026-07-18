import 'package:flutter/foundation.dart';

/// Centralized logging abstraction for the application.
abstract class AppLogger {
  void debug(String message, {Object? error, StackTrace? stackTrace});
  void info(String message, {Object? error, StackTrace? stackTrace});
  void warning(String message, {Object? error, StackTrace? stackTrace});
  void error(String message, {Object? error, StackTrace? stackTrace});
}

/// Default logger that prints to the debug console.
class ConsoleAppLogger implements AppLogger {
  const ConsoleAppLogger();

  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      _log('DEBUG', message, error: error, stackTrace: stackTrace);
    }
  }

  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) {
    _log('INFO', message, error: error, stackTrace: stackTrace);
  }

  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    _log('WARN', message, error: error, stackTrace: stackTrace);
  }

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log('ERROR', message, error: error, stackTrace: stackTrace);
  }

  void _log(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer('[AI Gallery][$level] $message');
    if (error != null) buffer.write(' | $error');
    debugPrint(buffer.toString());
    if (stackTrace != null && kDebugMode) {
      debugPrint(stackTrace.toString());
    }
  }
}
