import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/storage/secure_storage_service.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';

/// OpenAI Embedding Provider using text-embedding-3-small/large models.
///
/// Supports both image embeddings (via vision model) and text embeddings.
/// Requires an OpenAI API key with embeddings access.
class OpenAIEmbeddingProvider implements EmbeddingProvider {
  /// Creates an OpenAI embedding provider.
  ///
  /// [logger] - Application logger.
  /// [secureStorage] - Secure storage for API key retrieval.
  /// [model] - Embedding model to use ('text-embedding-3-small' or 'text-embedding-3-large').
  /// [dimensions] - Output dimensions (optional, for -3-large model only).
  OpenAIEmbeddingProvider({
    required AppLogger logger,
    required SecureStorageService secureStorage,
    this.model = 'text-embedding-3-small',
    this.dimensions,
  }) : _logger = logger,
       _secureStorage = secureStorage;

  final AppLogger _logger;
  final SecureStorageService _secureStorage;
  final String model;
  final int? dimensions;

  static const _baseUrl = 'https://api.openai.com/v1';
  static const _visionModel = 'gpt-4o-mini'; // For image analysis

  String? _cachedApiKey;
  bool _keyLoading = false;

  @override
  String get id => 'openai_$model';

  @override
  String get name => 'OpenAI $model';

  @override
  Future<bool> get isAvailable async {
    try {
      final key = await _getApiKey();
      return key != null && key.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves the OpenAI API key from secure storage.
  Future<String?> _getApiKey() async {
    if (_cachedApiKey != null) return _cachedApiKey;
    if (_keyLoading) return null;

    _keyLoading = true;
    try {
      _cachedApiKey = await _secureStorage.getOpenAIKey();
      return _cachedApiKey;
    } finally {
      _keyLoading = false;
    }
  }

  @override
  Future<Float32List> generateEmbedding(Uint8List imageBytes) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('OpenAI API key not configured');
    }

    // Convert image to base64 for vision model
    final base64Image = base64Encode(imageBytes);
    final imageUrl = 'data:image/jpeg;base64,$base64Image';

    try {
      // Use GPT-4o-mini vision to generate description, then embed that
      final description = await _analyzeImage(imageUrl, apiKey);
      return await generateTextEmbedding(description);
    } catch (e, st) {
      _logger.error('OpenAI image embedding failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<Float32List> generateTextEmbedding(String text) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('OpenAI API key not configured');
    }

    try {
      final requestBody = {
        'model': model,
        'input': text,
        if (dimensions != null) 'dimensions': dimensions,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/embeddings'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw StateError(
          'OpenAI API error: ${error['error']?['message'] ?? response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);
      final embeddingData = data['data'] as List;
      if (embeddingData.isEmpty) {
        throw StateError('No embedding returned from OpenAI');
      }

      final embedding = embeddingData.first['embedding'] as List;
      return Float32List.fromList(
        embedding.cast<double>().map((e) => e).toList(),
      );
    } catch (e, st) {
      _logger.error('OpenAI text embedding failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Analyze image using GPT-4o-mini vision model.
  Future<String> _analyzeImage(String imageUrl, String apiKey) async {
    final requestBody = {
      'model': _visionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': 'Describe this image in detail for semantic search. Include objects, scenes, people, text, colors, and mood.',
            },
            {'type': 'image_url', 'image_url': {'url': imageUrl}},
          ],
        },
      ],
      'max_tokens': 500,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw StateError(
        'OpenAI Vision API error: ${error['error']?['message'] ?? response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);
    final choices = data['choices'] as List;
    if (choices.isEmpty) {
      throw StateError('No response from OpenAI Vision');
    }

    final content = choices.first['message']['content'] as String?;
    return content ?? 'Image description unavailable';
  }

  /// Invalidates the cached API key (call after key update).
  void invalidateCache() {
    _cachedApiKey = null;
  }

  @override
  Future<Float32List> generateEmbeddingFromFace({
    required Uint8List imageBytes,
    required FaceDetection faceDetection,
  }) async {
    // OpenAI doesn't have face-specific embeddings; fall back to general image embedding
    return generateEmbedding(imageBytes);
  }

  @override
  Future<void> initialize() async {
    await _getApiKey();
    _logger.info('OpenAIEmbeddingProvider initialized');
  }

  @override
  Future<void> warmUp() async {
    // No warm-up needed for cloud API
  }

  @override
  Future<void> dispose() async {
    invalidateCache();
  }
}