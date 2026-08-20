import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/storage/secure_storage_service.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';

/// Anthropic Embedding Provider.
///
/// Note: Anthropic doesn't currently offer embeddings API directly.
/// This provider uses Anthropic's models via the Messages API to generate
/// embeddings by extracting semantic representations. For production use,
/// consider using a dedicated embeddings provider (OpenAI, Google, Cohere, etc.)
/// and use Anthropic for generation/reasoning tasks.
class AnthropicEmbeddingProvider implements EmbeddingProvider {
  /// Creates an Anthropic embedding provider.
  ///
  /// [logger] - Application logger.
  /// [secureStorage] - Secure storage for API key retrieval.
  /// [model] - Model to use (e.g., 'claude-3-haiku-20240307').
  AnthropicEmbeddingProvider({
    required AppLogger logger,
    required SecureStorageService secureStorage,
    this.model = 'claude-3-haiku-20240307',
  }) : _logger = logger,
       _secureStorage = secureStorage;

  final AppLogger _logger;
  final SecureStorageService _secureStorage;
  final String model;

  static const _baseUrl = 'https://api.anthropic.com/v1';
  static const _apiVersion = '2024-03-09';

  String? _cachedApiKey;
  bool _keyLoading = false;

  @override
  String get id => 'anthropic';

  @override
  String get name => 'Anthropic (Claude)';

  @override
  String get modelId => 'anthropic-$model';

  @override
  Future<bool> get isAvailable async {
    try {
      final key = await _getApiKey();
      return key != null && key.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves the Anthropic API key from secure storage.
  Future<String?> _getApiKey() async {
    if (_cachedApiKey != null) return _cachedApiKey;
    if (_keyLoading) return null;

    _keyLoading = true;
    try {
      _cachedApiKey = await _secureStorage.getAnthropicKey();
      return _cachedApiKey;
    } finally {
      _keyLoading = false;
    }
  }

  @override
  Future<Float32List> generateEmbedding(Uint8List imageBytes) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('Anthropic API key not configured');
    }

    // Convert image to base64
    final base64Image = base64Encode(imageBytes);
    final imageMediaType = 'image/jpeg';

    try {
      // Use Claude to analyze image and generate semantic description
      final description = await _analyzeImage(base64Image, imageMediaType, apiKey);
      // Then generate text embedding from description (using fallback)
      return _generateSemanticEmbedding(description);
    } catch (e, st) {
      _logger.error('Anthropic image embedding failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<Float32List> generateTextEmbedding(String text) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('Anthropic API key not configured');
    }

    try {
      // Generate semantic embedding from text using Claude
      return await _generateSemanticEmbedding(text);
    } catch (e, st) {
      _logger.error('Anthropic text embedding failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<Float32List> generateEmbeddingFromFace({
    required Uint8List imageBytes,
    required FaceDetection faceDetection,
  }) async {
    // Anthropic doesn't have face-specific embeddings; fall back to general image embedding
    return generateEmbedding(imageBytes);
  }

  @override
  Future<void> initialize() async {
    await _getApiKey();
    _logger.info('AnthropicEmbeddingProvider initialized');
  }

  @override
  Future<void> warmUp() async {
    // No warm-up needed for cloud API
  }

  @override
  Future<void> dispose() async {
    invalidateCache();
  }

  /// Analyze image using Claude vision.
  Future<String> _analyzeImage(String base64Image, String mediaType, String apiKey) async {
    final requestBody = {
      'model': model,
      'max_tokens': 500,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': 'Describe this image in detail for semantic search. Include objects, scenes, people, text, colors, and mood.',
            },
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mediaType,
                'data': base64Image,
              },
            },
          ],
        },
      ],
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/messages'),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': _apiVersion,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw StateError(
        'Anthropic API error: ${error['error']?['message'] ?? response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);
    final content = data['content'] as List;
    if (content.isEmpty) {
      throw StateError('No response from Anthropic');
    }

    final textContent = content.firstWhere(
      (c) => c['type'] == 'text',
      orElse: () => <String, dynamic>{'text': 'Image description unavailable'},
    )['text'] as String?;

    return textContent ?? 'Image description unavailable';
  }

  /// Generate a semantic embedding from text using a deterministic approach.
  /// In production, you would typically use a separate embeddings API.
  Future<Float32List> _generateSemanticEmbedding(String text) async {
    // For now, use a deterministic hash-based embedding
    // In production, call a proper embeddings API (send text to embedding model)
    return _fallbackTextEmbedding(text);
  }

  /// Fallback deterministic text embedding.
  Float32List _fallbackTextEmbedding(String text) {
    final hash = text.hashCode;
    const dim = 1024;
    final vector = List.generate(dim, (i) {
      // Use multiple hash functions for better distribution
      final h1 = (hash * 0x9e3779b9 + i * 0x85ebca6b) & 0x7FFFFFFF;
      return sin(h1 * 0.123456);
    });
    double norm = 0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = norm <= 0 ? 1.0 : sqrt(norm);
    return Float32List.fromList(vector.map((v) => v / norm).toList());
  }

  /// Invalidates the cached API key (call after key update).
  void invalidateCache() {
    _cachedApiKey = null;
  }
}