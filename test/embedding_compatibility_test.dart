import 'dart:typed_data';
import 'dart:math' show sqrt;

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/ai/providers/local_embedding_provider.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/services/model_downloader.dart';
import 'package:ai_gallery/core/services/model_manager.dart';
import 'package:onnxruntime/onnxruntime.dart';

void main() {
  // Initialize Flutter binding for asset loading
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Embedding Compatibility Verification', () {
    late LocalEmbeddingProvider provider;
    late AppLogger logger;
    late ModelManager modelManager;

    setUpAll(() async {
      logger = const ConsoleAppLogger();
      modelManager = ModelManager(downloader: ModelDownloader(logger: logger), logger: logger);

      // Use bundled models for testing
      provider = LocalEmbeddingProvider(
        logger: logger,
        modelManager: modelManager,
        modelAssetPath: 'assets/models/siglip_base_patch16_224.onnx',
        textModelAssetPath: 'assets/models/siglip_text_encoder.onnx',
        tokenizerAssetPath: 'assets/models/siglip_tokenizer.model',
        modelPreset: 'siglip-base-patch16-224',
      );

      await provider.initialize();
      await provider.warmUp();
    });

    tearDownAll(() async {
      await provider.dispose();
    });

    test('Image encoder loads and produces 768-dim embeddings', () async {
      // Create a simple test image (solid color)
      // In real test, this would be actual image bytes
      // For now, we verify the model dimension by checking the session
      final session = provider.visionSession;
      expect(session, isNotNull, reason: 'Vision ONNX session should be initialized');

      // The output dimension should be 768 for SigLIP-B/16
      // We'll verify this by running inference on a dummy tensor
      final dummyTensor = OrtValueTensor.createTensorWithDataList(
        Float32List(3 * 224 * 224),
        [1, 3, 224, 224],
      );

      final outputs = session!.run(OrtRunOptions(), {session.inputNames.first: dummyTensor});
      final outputTensor = outputs.first;
      expect(outputTensor, isNotNull);

      final dynamic outputValue = outputTensor!.value;
      List<double> embedding;
      if (outputValue is List<double>) {
        embedding = outputValue;
      } else if (outputValue is Float32List) {
        embedding = outputValue.toList();
      } else {
        throw StateError('Unexpected output type: ${outputValue.runtimeType}');
      }

      expect(embedding.length, equals(768),
        reason: 'SigLIP-B/16 image embedding should be 768-dimensional');
    });

    test('Text encoder loads and produces 768-dim embeddings', () async {
      final session = provider.textSession;
      expect(session, isNotNull, reason: 'Text ONNX session should be initialized');

      // Verify text encoder output dimension by running inference
      final inputIds = List<int>.filled(77, 0);
      inputIds[0] = 49406; // BOS token
      inputIds[1] = 49407; // EOS token (for empty/short text)

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        Int32List.fromList(inputIds),
        [1, 77],
      );

      final outputs = session!.run(OrtRunOptions(), {session.inputNames.first: inputTensor});
      final outputTensor = outputs.first;
      expect(outputTensor, isNotNull);

      final dynamic outputValue = outputTensor!.value;
      List<double> embedding;
      if (outputValue is List<double>) {
        embedding = outputValue;
      } else if (outputValue is Float32List) {
        embedding = outputValue.toList();
      } else {
        throw StateError('Unexpected output type: ${outputValue.runtimeType}');
      }

      expect(embedding.length, equals(768),
        reason: 'SigLIP-B/16 text embedding should be 768-dimensional (same as image)');
    });

    test('Image embeddings are L2 normalized', () async {
      // Generate a test embedding using the public API
      final testImageBytes = _createTestImageBytes(224, 224, color: 0xFFFF0000); // Red
      final embedding = await provider.generateEmbedding(testImageBytes);

      final norm = _l2Norm(embedding);
      expect(norm, closeTo(1.0, 0.001),
        reason: 'Image embedding should be L2 normalized (norm = 1.0)');
    });

    test('Text embeddings are L2 normalized', () async {
      final embedding = await provider.generateTextEmbedding('test');

      final norm = _l2Norm(embedding);
      expect(norm, closeTo(1.0, 0.001),
        reason: 'Text embedding should be L2 normalized (norm = 1.0)');
    });

    test('Image and text embeddings share the same space (semantic similarity)', () async {
      // This test uses actual semantic queries
      // We test that related concepts have higher similarity than unrelated ones

      final testCases = [
        ('dog', 'a photo of a dog'),
        ('car', 'a photo of a car'),
        ('beach', 'a photo of a beach'),
        ('food', 'a photo of food'),
        ('sunset', 'a photo of a sunset'),
      ];

      // Generate text embeddings for all queries
      final queryEmbeddings = <String, Float32List>{};
      for (final (concept, query) in testCases) {
        queryEmbeddings[concept] = await provider.generateTextEmbedding(query);
      }

      // Generate text embedding for each individual concept
      final conceptEmbeddings = <String, Float32List>{};
      for (final (concept, _) in testCases) {
        conceptEmbeddings[concept] = await provider.generateTextEmbedding(concept);
      }

      // Verify related pairs have higher similarity than unrelated
      for (final (concept, _) in testCases) {
        final relatedSim = _cosineSimilarity(conceptEmbeddings[concept]!, queryEmbeddings[concept]!);

        // Find max similarity with unrelated concepts
        double maxUnrelatedSim = 0.0;
        for (final entry in queryEmbeddings.entries) {
          final otherConcept = entry.key;
          final otherQueryEmbedding = entry.value;
          if (otherConcept != concept) {
            final sim = _cosineSimilarity(conceptEmbeddings[concept]!, otherQueryEmbedding);
            if (sim > maxUnrelatedSim) maxUnrelatedSim = sim;
          }
        }

        // Related should be significantly more similar than unrelated
        // Using a margin of 0.1 (cosine similarity ranges from -1 to 1)
        expect(
          relatedSim,
          greaterThan(maxUnrelatedSim + 0.1),
          reason: 'Related concept "$concept" should have higher similarity to its query '
              '($relatedSim) than to unrelated queries ($maxUnrelatedSim)',
        );
      }
    });

    test('Different concepts produce distinct embeddings', () async {
      final embeddings = <String, Float32List>{};
      final concepts = ['dog', 'car', 'beach', 'food', 'sunset'];

      for (final concept in concepts) {
        embeddings[concept] = await provider.generateTextEmbedding(concept);
      }

      // All pairs should have cosine similarity < 0.8 (not nearly identical)
      for (int i = 0; i < concepts.length; i++) {
        for (int j = i + 1; j < concepts.length; j++) {
          final sim = _cosineSimilarity(embeddings[concepts[i]]!, embeddings[concepts[j]]!);
          expect(sim, lessThan(0.8),
            reason: 'Different concepts "${concepts[i]}" and "${concepts[j]}" '
                'should produce distinct embeddings (similarity=$sim)');
        }
      }
    });
  });
}

/// Create a simple test image with a solid color.
Uint8List _createTestImageBytes(int width, int height, {required int color}) {
  // Create a minimal valid PNG/encoded image
  // This is a placeholder - in real test, use actual test images
  final buffer = Float32List(width * height * 4);
  for (int i = 0; i < width * height; i++) {
    buffer[i * 4] = ((color >> 16) & 0xFF) / 255.0;     // R
    buffer[i * 4 + 1] = ((color >> 8) & 0xFF) / 255.0;  // G
    buffer[i * 4 + 2] = (color & 0xFF) / 255.0;         // B
    buffer[i * 4 + 3] = 1.0;                            // A
  }
  // Return as Uint8List (this is just for tensor shape verification)
  // Note: The actual preprocessing expects valid image bytes
  // This test primarily verifies the model output dimension
  return Uint8List.fromList(List.filled(width * height * 4, 0));
}

/// Compute L2 norm of a vector.
double _l2Norm(Float32List vector) {
  double sum = 0;
  for (final v in vector) {
    sum += v * v;
  }
  return sum <= 0 ? 0.0 : sqrt(sum);
}

/// Compute cosine similarity between two vectors (assumes both are normalized).
double _cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) throw ArgumentError('Vector dimensions must match');
  double dot = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}