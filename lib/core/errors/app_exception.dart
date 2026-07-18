/// Base class for application-specific exceptions.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  /// Human-readable error description.
  final String message;

  /// Underlying cause, if any.
  final Object? cause;

  @override
  String toString() => 'AppException: $message';
}

/// Thrown when photo library permission is denied.
final class PermissionDeniedException extends AppException {
  const PermissionDeniedException([super.message = 'Photo library permission denied']);
}

/// Thrown when a database operation fails.
final class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.cause});
}

/// Thrown when a requested resource is not found.
final class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

/// Thrown when an AI operation fails.
final class AiException extends AppException {
  const AiException(super.message, {super.cause});
}

/// Thrown when a required API key is missing.
final class ApiKeyMissingException extends AppException {
  const ApiKeyMissingException([super.message = 'Required API key is not configured']);
}

/// Maps an arbitrary error to a user-facing message string.
String userFacingMessage(Object error) {
  return switch (error) {
    PermissionDeniedException(:final message) => message,
    ApiKeyMissingException(:final message) => message,
    AppException(:final message) => message,
    _ => 'Something went wrong. Please try again.',
  };
}
