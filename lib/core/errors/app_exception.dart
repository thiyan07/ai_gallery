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

// ── Permission ──

/// Thrown when photo library permission is denied.
final class PermissionDeniedException extends AppException {
  const PermissionDeniedException([
    super.message = 'Photo library permission denied',
  ]);
}

// ── Database ──

/// Thrown when a database operation fails.
final class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.cause});
}

/// Thrown when a database migration fails.
final class MigrationException extends AppException {
  const MigrationException(super.message, {super.cause});
}

// ── Not Found ──

/// Thrown when a requested resource is not found.
final class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

// ── AI / ML ──

/// Thrown when an AI operation fails (general).
final class AiException extends AppException {
  const AiException(super.message, {super.cause});
}

/// Thrown when an ONNX model fails to load.
final class ModelLoadException extends AppException {
  const ModelLoadException(super.message, {super.cause});
}

/// Thrown when ONNX model inference fails.
final class ModelInferenceException extends AppException {
  const ModelInferenceException(super.message, {super.cause});
}

/// Thrown when face detection or processing fails.
final class FaceProcessingException extends AppException {
  const FaceProcessingException(super.message, {super.cause});
}

/// Thrown when embedding generation fails.
final class EmbeddingException extends AppException {
  const EmbeddingException(super.message, {super.cause});
}

/// Thrown when vector index operations fail.
final class VectorIndexException extends AppException {
  const VectorIndexException(super.message, {super.cause});
}

// ── File / Storage ──

/// Thrown when a file operation fails (read, write, delete).
final class FileAccessError extends AppException {
  const FileAccessError(super.message, {super.cause});
}

/// Thrown when image decoding fails.
final class ImageDecodeException extends AppException {
  const ImageDecodeException(super.message, {super.cause});
}

/// Thrown when storage quota is exceeded or storage is unavailable.
final class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

// ── API ──

/// Thrown when a required API key is missing.
final class ApiKeyMissingException extends AppException {
  const ApiKeyMissingException([
    super.message = 'Required API key is not configured',
  ]);
}

/// Maps an arbitrary error to a user-facing message string.
String userFacingMessage(Object error) {
  return switch (error) {
    PermissionDeniedException(:final message) => message,
    ApiKeyMissingException(:final message) => message,
    ModelLoadException() => 'AI models could not be loaded. Please check storage.',
    ModelInferenceException() => 'AI analysis failed. Please try again.',
    FaceProcessingException() => 'Face detection failed.',
    EmbeddingException() => 'Image analysis failed.',
    FileAccessError(:final message) => message,
    ImageDecodeException() => 'This image could not be read.',
    StorageException() => 'Not enough storage space.',
    MigrationException() => 'Database upgrade failed. Data may need repair.',
    AppException(:final message) => message,
    _ => 'Something went wrong. Please try again.',
  };
}
