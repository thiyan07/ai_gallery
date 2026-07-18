import 'dart:typed_data';

/// Interface for generating embeddings for photos.
///
/// Implementations may use:
/// - SigLIP
/// - CLIP
/// - Gemini Embeddings
/// - OpenAI Embeddings
/// - Custom models
abstract class EmbeddingProvider {
  /// Unique identifier for this provider.
  String get id;

  /// Human-readable name for this provider.
  String get name;

  /// Whether this provider is available (e.g., API key configured).
  Future<bool> get isAvailable;

  /// Generates an embedding for the given image bytes.
  ///
  /// Returns the embedding as a list of floats.
  Future<Float32List> generateEmbedding(Uint8List imageBytes);

  /// Generates an embedding for the given text.
  Future<Float32List> generateTextEmbedding(String text);
}
