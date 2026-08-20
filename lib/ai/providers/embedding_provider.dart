import 'dart:typed_data';

import '../../domain/models/face_detection.dart';

/// Interface for generating embeddings for photos.
///
/// Implementations may use:
/// - SigLIP
/// - CLIP
/// - Gemini Embeddings
/// - OpenAI Embeddings
/// - Custom models
abstract class EmbeddingProvider {
  /// Unique identifier for this provider (e.g., "local_siglip-base-patch16-224").
  String get id;

  /// Human-readable name for this provider.
  String get name;

  /// The actual model ID/version used for embedding generation.
  /// This is stored with embeddings to prevent mixing embeddings from different models.
  /// Examples: "siglip-base-patch16-224", "mobileclip-s1", "clip-vit-base-patch32"
  String get modelId;

  /// Whether this provider is available (e.g., API key configured).
  Future<bool> get isAvailable;

  /// Generates an embedding for the given image bytes.
  ///
  /// Returns the embedding as a list of floats.
  Future<Float32List> generateEmbedding(Uint8List imageBytes);

  /// Generates an embedding for the given text.
  Future<Float32List> generateTextEmbedding(String text);

  /// Generates a face embedding using face alignment (eye keypoints).
  ///
  /// This method is only implemented by face-specific embedding providers.
  /// It aligns the face using eye keypoints from the FaceDetection before
  /// generating the embedding for better recognition accuracy.
  ///
  /// [imageBytes] - Full image bytes
  /// [faceDetection] - Face detection with keypoints for alignment
  ///
  /// Default implementation throws UnimplementedError.
  Future<Float32List> generateEmbeddingFromFace({
    required Uint8List imageBytes,
    required FaceDetection faceDetection,
  }) async {
    throw UnimplementedError('generateEmbeddingFromFace not implemented for this provider');
  }

  /// Initialize the provider.
  Future<void> initialize();

  /// Warm up the model (run dummy inference).
  Future<void> warmUp();

  /// Dispose resources.
  Future<void> dispose();
}
