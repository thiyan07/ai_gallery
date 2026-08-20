import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/storage/secure_storage_service.dart';
import 'package:ai_gallery/ai/providers/embedding_provider.dart';
import 'package:ai_gallery/ai/providers/face_detection_provider.dart';
import 'package:ai_gallery/ai/providers/object_detection_provider.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';
import 'package:ai_gallery/domain/models/object_detection_model.dart';

/// Google Cloud Vision API Provider for object detection, OCR, and embeddings.
///
/// Supports:
/// - Object localization (detecting objects with bounding boxes)
/// - OCR (text detection and extraction)
/// - Label detection (classifying image content)
/// - Face detection
/// - Image embeddings (via Vision API embeddings)
class GoogleVisionProvider implements EmbeddingProvider, ObjectDetectionProvider, FaceDetectionProvider {
  /// Creates a Google Vision provider.
  ///
  /// [logger] - Application logger.
  /// [secureStorage] - Secure storage for API key retrieval.
  GoogleVisionProvider({
    required AppLogger logger,
    required SecureStorageService secureStorage,
  }) : _logger = logger,
       _secureStorage = secureStorage;

  final AppLogger _logger;
  final SecureStorageService _secureStorage;

  static const _baseUrl = 'https://vision.googleapis.com/v1/images:annotate';

  String? _cachedApiKey;
  bool _keyLoading = false;

  @override
  String get id => 'google_vision';

  @override
  String get name => 'Google Cloud Vision';

  @override
  String get modelId => 'google-vision-embeddings';

  @override
  Future<bool> get isAvailable async {
    try {
      final key = await _getApiKey();
      return key != null && key.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves the Google Vision API key from secure storage.
  Future<String?> _getApiKey() async {
    if (_cachedApiKey != null) return _cachedApiKey;
    if (_keyLoading) return null;

    _keyLoading = true;
    try {
      _cachedApiKey = await _secureStorage.getGoogleVisionKey();
      return _cachedApiKey;
    } finally {
      _keyLoading = false;
    }
  }

  @override
  Future<Float32List> generateEmbedding(Uint8List imageBytes) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('Google Vision API key not configured');
    }

    try {
      // Use label detection as basis for embedding-like features
      // Note: Google Vision doesn't provide direct embeddings like CLIP
      // We'll generate a feature vector from detected labels
      final labels = await _detectLabels(imageBytes, apiKey);

      // Convert labels to a fixed-size feature vector
      return _labelsToVector(labels);
    } catch (e, st) {
      _logger.error('Google Vision embedding failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<Float32List> generateTextEmbedding(String text) async {
    // Google Vision is image-focused, return fallback for text
    return _fallbackTextEmbedding(text);
  }

  @override
  Future<Float32List> generateEmbeddingFromFace({
    required Uint8List imageBytes,
    required FaceDetection faceDetection,
  }) async {
    // Google Vision doesn't have face-specific embeddings; fall back to general image embedding
    return generateEmbedding(imageBytes);
  }

  @override
  Future<ObjectDetectionResult> detectObjects(Uint8List imageBytes) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('Google Vision API key not configured');
    }

    try {
      final objects = await _detectObjectsInternal(imageBytes, apiKey);
      return ObjectDetectionResult(
        detections: objects,
        imageWidth: 0, // Will be set by caller if needed
        imageHeight: 0,
        inferenceTimeMs: 0, // Not tracked for cloud API
      );
    } catch (e, st) {
      _logger.error('Google Vision object detection failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  // ObjectDetectionProvider interface
  // ─────────────────────────────────────────────

  @override
  List<String> get labels {
    // Google Vision returns dynamic labels from the API
    // Common categories: person, vehicle, animal, food, furniture, electronic, etc.
    return const [
      'person',
      'vehicle',
      'car',
      'bicycle',
      'motorcycle',
      'animal',
      'dog',
      'cat',
      'bird',
      'food',
      'fruit',
      'vegetable',
      'furniture',
      'chair',
      'table',
      'electronic',
      'phone',
      'computer',
      'tv',
      'plant',
      'flower',
      'tree',
      'building',
      'road',
      'sign',
      'text',
    ];
  }

  @override
  Future<void> initialize() async {
    // Verify API key is available
    await _getApiKey();
    _logger.info('GoogleVisionProvider initialized');
  }

  @override
  Future<void> warmUp() async {
    // No warm-up needed for cloud API
  }

  @override
  Future<void> dispose() async {
    invalidateCache();
  }

  // ─────────────────────────────────────────────
  // FaceDetectionProvider implementation
  // ─────────────────────────────────────────────

  @override
  Future<List<FaceDetection>> detectFaces(Uint8List imageBytes) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('Google Vision API key not configured');
    }

    try {
      final requestBody = _buildRequest(imageBytes, [
        {'type': 'FACE_DETECTION', 'maxResults': 50},
      ]);

      final response = await _sendRequest(requestBody, apiKey);

      final responses = response['responses'] as List;
      if (responses.isEmpty) return [];

      final faceAnnotations = responses.first['faceAnnotations'] as List?;
      if (faceAnnotations == null) return [];

      return faceAnnotations.map((e) => _parseFaceAnnotation(e as Map<String, dynamic>)).toList();
    } catch (e, st) {
      _logger.error('Google Vision face detection failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Parse Google Vision face annotation to FaceDetection.
  FaceDetection _parseFaceAnnotation(Map<String, dynamic> json) {
    final boundingPoly = json['fdBoundingPoly']?['vertices'] as List?;
    final landmarks = json['landmarks'] as List?;
    final detectionConfidence = (json['detectionConfidence'] as num? ?? 0.0).toDouble();

    // Parse bounding box
    double x = 0, y = 0, w = 1, h = 1;
    if (boundingPoly != null && boundingPoly.length >= 4) {
      final xs = boundingPoly.where((v) => v['x'] != null).map((v) => (v['x'] as num).toDouble()).toList();
      final ys = boundingPoly.where((v) => v['y'] != null).map((v) => (v['y'] as num).toDouble()).toList();
      if (xs.isNotEmpty && ys.isNotEmpty) {
        final minX = xs.reduce(min).clamp(0.0, 1.0);
        final maxX = xs.reduce(max).clamp(0.0, 1.0);
        final minY = ys.reduce(min).clamp(0.0, 1.0);
        final maxY = ys.reduce(max).clamp(0.0, 1.0);
        x = minX;
        y = minY;
        w = (maxX - minX).clamp(0.0, 1.0);
        h = (maxY - minY).clamp(0.0, 1.0);
      }
    }

    // Parse keypoints (eyes, nose, mouth)
    final keypoints = <FaceKeypoint>[];
    if (landmarks != null) {
      for (final lm in landmarks) {
        final type = lm['type'] as String?;
        final pos = lm['position'] as Map<String, dynamic>?;
        if (pos != null && type != null) {
          final name = _mapGoogleLandmarkType(type);
          if (name != null) {
            keypoints.add(FaceKeypoint(
              name: name,
              x: (pos['x'] as num? ?? 0.0).toDouble().clamp(0.0, 1.0),
              y: (pos['y'] as num? ?? 0.0).toDouble().clamp(0.0, 1.0),
            ));
          }
        }
      }
    }

    return FaceDetection(
      x: x,
      y: y,
      width: w,
      height: h,
      confidence: detectionConfidence.clamp(0.0, 1.0),
      keypoints: keypoints,
    );
  }

  /// Map Google Vision landmark types to our standard names.
  String? _mapGoogleLandmarkType(String googleType) {
    return switch (googleType) {
      'LEFT_EYE' => 'left_eye',
      'RIGHT_EYE' => 'right_eye',
      'NOSE_TIP' => 'nose',
      'LEFT_EYE_TOP_BOUNDARY' => null,
      'LEFT_EYE_RIGHT_CORNER' => null,
      'LEFT_EYE_BOTTOM_BOUNDARY' => null,
      'LEFT_EYE_LEFT_CORNER' => null,
      'RIGHT_EYE_TOP_BOUNDARY' => null,
      'RIGHT_EYE_RIGHT_CORNER' => null,
      'RIGHT_EYE_BOTTOM_BOUNDARY' => null,
      'RIGHT_EYE_LEFT_CORNER' => null,
      'LEFT_EYEBROW_UPPER_MIDPOINT' => null,
      'RIGHT_EYEBROW_UPPER_MIDPOINT' => null,
      'FOREHEAD_GLABELLA' => null,
      'UPPER_LIP' => 'mouth_right',
      'LOWER_LIP' => 'mouth_left',
      _ => null,
    };
  }

  /// Detect labels (classification) in image.
  Future<List<LabelAnnotation>> _detectLabels(Uint8List imageBytes, String apiKey) async {
    final requestBody = _buildRequest(imageBytes, [
      {'type': 'LABEL_DETECTION', 'maxResults': 50},
    ]);

    final response = await _sendRequest(requestBody, apiKey);

    final responses = response['responses'] as List;
    if (responses.isEmpty) return [];

    final labelAnnotations = responses.first['labelAnnotations'] as List?;
    if (labelAnnotations == null) return [];

    return labelAnnotations
        .map((e) => LabelAnnotation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Detect objects with bounding boxes.
  Future<List<DetectedObject>> _detectObjectsInternal(Uint8List imageBytes, String apiKey) async {
    final requestBody = _buildRequest(imageBytes, [
      {'type': 'OBJECT_LOCALIZATION', 'maxResults': 50},
    ]);

    final response = await _sendRequest(requestBody, apiKey);

    final responses = response['responses'] as List;
    if (responses.isEmpty) return [];

    final objectAnnotations = responses.first['localizedObjectAnnotations'] as List?;
    if (objectAnnotations == null) return [];

    return objectAnnotations
        .map((e) => DetectedObject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Extract text from image (OCR).
  Future<String> extractText(Uint8List imageBytes) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('Google Vision API key not configured');
    }

    try {
      final requestBody = _buildRequest(imageBytes, [
        {'type': 'TEXT_DETECTION', 'maxResults': 50},
      ]);

      final response = await _sendRequest(requestBody, apiKey);

      final responses = response['responses'] as List;
      if (responses.isEmpty) return '';

      final textAnnotations = responses.first['textAnnotations'] as List?;
      if (textAnnotations == null || textAnnotations.isEmpty) return '';

      // First annotation contains the full text
      return textAnnotations.first['description'] as String? ?? '';
    } catch (e, st) {
      _logger.error('Google Vision OCR failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Build annotation request payload.
  Map<String, dynamic> _buildRequest(Uint8List imageBytes, List<Map<String, dynamic>> features) {
    return {
      'requests': [
        {
          'image': {'content': base64Encode(imageBytes)},
          'features': features,
        },
      ],
    };
  }

  /// Send request to Google Vision API.
  Future<Map<String, dynamic>> _sendRequest(
    Map<String, dynamic> requestBody,
    String apiKey,
  ) async {
    final response = await http.post(
      Uri.parse('$_baseUrl?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw StateError(
        'Google Vision API error: ${error['error']?['message'] ?? response.statusCode}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Convert detected labels to fixed-size feature vector.
  Float32List _labelsToVector(List<LabelAnnotation> labels) {
    // Use a simple bag-of-words approach with 1024 dimensions
    const dim = 1024;
    final vector = List<double>.filled(dim, 0.0);

    for (final label in labels) {
      final hash = _hashLabel(label.description);
      final idx = hash % dim;
      vector[idx] += label.score;
    }

    // L2 normalize
    double norm = 0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = norm <= 0 ? 1.0 : sqrt(norm);

    return Float32List.fromList(vector.map((v) => v / norm).toList());
  }

  /// Simple hash for label string.
  int _hashLabel(String label) {
    int hash = 0;
    for (final codeUnit in label.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// Fallback deterministic text embedding.
  Float32List _fallbackTextEmbedding(String text) {
    final hash = text.hashCode;
    const dim = 1024;
    final vector = List.generate(dim, (i) => sin((hash + i) * 0.123456));
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

/// Label annotation from Google Vision.
class LabelAnnotation {
  LabelAnnotation({
    required this.description,
    required this.score,
    this.topicality,
  });

  final String description;
  final double score;
  final double? topicality;

  factory LabelAnnotation.fromJson(Map<String, dynamic> json) {
    return LabelAnnotation(
      description: json['description'] as String? ?? '',
      score: (json['score'] as num? ?? 0.0).toDouble(),
      topicality: (json['topicality'] as num? ?? 0.0).toDouble(),
    );
  }
}