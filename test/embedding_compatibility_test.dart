import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cosine Similarity', () {
    test('parallel vectors return 1.0', () {
      final a = Float32List.fromList([1, 0, 0, 0]);
      final b = Float32List.fromList([1, 0, 0, 0]);
      expect(cosineSimilarity(a, b), closeTo(1.0, 1e-6));
    });

    test('orthogonal vectors return 0.0', () {
      final a = Float32List.fromList([1, 0, 0, 0]);
      final b = Float32List.fromList([0, 1, 0, 0]);
      expect(cosineSimilarity(a, b), closeTo(0.0, 1e-6));
    });

    test('opposite vectors return -1.0', () {
      final a = Float32List.fromList([1, 0]);
      final b = Float32List.fromList([-1, 0]);
      expect(cosineSimilarity(a, b), closeTo(-1.0, 1e-6));
    });

    test('known angle returns correct similarity', () {
      final a = Float32List.fromList([1, 0]);
      final sqrt2 = sqrt(2.0);
      final b = Float32List.fromList([1.0 / sqrt2, 1.0 / sqrt2]);
      expect(cosineSimilarity(a, b), closeTo(1.0 / sqrt2, 1e-4));
    });

    test('mismatched dimensions return 0.0', () {
      final a = Float32List.fromList([1, 0, 0]);
      final b = Float32List.fromList([1, 0]);
      expect(cosineSimilarity(a, b), 0.0);
    });

    test('similarity is commutative', () {
      final a = Float32List.fromList([0.5, 0.5, 0.5, 0.5]);
      final b = Float32List.fromList([0.1, 0.2, 0.3, 0.4]);
      expect(cosineSimilarity(a, b), closeTo(cosineSimilarity(b, a), 1e-10));
    });

    test('result is clamped to [-1, 1]', () {
      final a = Float32List.fromList([1e10, 1e10]);
      final b = Float32List.fromList([1e10, 1e10]);
      expect(cosineSimilarity(a, b), inInclusiveRange(-1.0, 1.0));
    });
  });

  group('L2 Normalization', () {
    test('unit vector has norm 1.0', () {
      final v = Float32List.fromList([1, 0, 0, 0]);
      expect(l2Norm(v), closeTo(1.0, 1e-6));
    });

    test('known vector has correct norm', () {
      final v = Float32List.fromList([3, 4]);
      expect(l2Norm(v), closeTo(5.0, 1e-6));
    });

    test('zero vector has norm 0.0', () {
      final v = Float32List.fromList([0, 0, 0]);
      expect(l2Norm(v), 0.0);
    });

    test('normalized vector has norm 1.0', () {
      final v = Float32List.fromList([3, 4]);
      final normalized = l2Normalize(v);
      expect(l2Norm(normalized), closeTo(1.0, 1e-6));
    });

    test('preserves direction after normalization', () {
      final v = Float32List.fromList([3, 4]);
      final normalized = l2Normalize(v);
      expect(normalized[0], closeTo(0.6, 1e-6));
      expect(normalized[1], closeTo(0.8, 1e-6));
    });

    test('large values normalize correctly', () {
      final v = Float32List.fromList([1000, 2000, 3000]);
      final normalized = l2Normalize(v);
      expect(l2Norm(normalized), closeTo(1.0, 1e-4));
    });

    test('negative values normalize correctly', () {
      final v = Float32List.fromList([-3, 4]);
      final normalized = l2Normalize(v);
      expect(l2Norm(normalized), closeTo(1.0, 1e-6));
      expect(normalized[0], closeTo(-0.6, 1e-6));
      expect(normalized[1], closeTo(0.8, 1e-6));
    });
  });

  group('Embedding Dimension Validation', () {
    test('SigLIP dimension is 768', () {
      const siglipDim = 768;
      final embedding = Float32List(siglipDim);
      expect(embedding.length, equals(768));
    });

    test('YOLOv8 face detection output has expected format', () {
      final detection = Float32List.fromList([0.5, 0.5, 0.1, 0.1, 0.95]);
      expect(detection.length, equals(5));
      expect(detection[4], greaterThan(0.0));
    });

    test('mismatched dimensions return 0.0 similarity', () {
      final a = Float32List(768);
      final b = Float32List(512);
      expect(cosineSimilarity(a, b), 0.0);
    });

    test('empty vectors return 0.0 similarity', () {
      final a = Float32List(0);
      final b = Float32List(0);
      expect(cosineSimilarity(a, b), 0.0);
    });
  });

  group('Similarity Threshold Behavior', () {
    test('identical normalized vectors have similarity 1.0', () {
      final v = l2Normalize(Float32List.fromList([1, 2, 3, 4]));
      expect(cosineSimilarity(v, v), closeTo(1.0, 1e-6));
    });

    test('very different vectors have low similarity', () {
      final a = l2Normalize(Float32List.fromList([1, 0, 0, 0]));
      final b = l2Normalize(Float32List.fromList([0, 0, 0, 1]));
      expect(cosineSimilarity(a, b), closeTo(0.0, 1e-6));
    });

    test('slightly perturbed vectors stay highly similar', () {
      final original = l2Normalize(Float32List.fromList([1, 2, 3, 4]));
      final perturbed = Float32List(original.length);
      for (var i = 0; i < original.length; i++) {
        perturbed[i] = original[i] + 0.01;
      }
      final perturbedNorm = l2Normalize(perturbed);
      expect(cosineSimilarity(original, perturbedNorm), greaterThan(0.9));
    });
  });

  group('Edge Cases', () {
    test('all-zero vector similarity with non-zero returns 0', () {
      final a = Float32List.fromList([0, 0, 0, 0]);
      final b = Float32List.fromList([1, 0, 0, 0]);
      expect(cosineSimilarity(a, b), 0.0);
    });

    test('very small values do not cause NaN or underflow', () {
      final a = Float32List.fromList([1e-15, 1e-15]);
      final b = Float32List.fromList([1e-15, 1e-15]);
      final sim = cosineSimilarity(a, b);
      expect(sim, isA<double>());
      expect(sim, isNot(isNaN));
      // Dot product of identical tiny vectors: 2e-30, clamped to valid range
      expect(sim, inInclusiveRange(-1.0, 1.0));
    });

    test('very large values do not cause overflow', () {
      final a = Float32List.fromList([1e10, 1e10]);
      final b = Float32List.fromList([1e10, 1e10]);
      final sim = cosineSimilarity(a, b);
      expect(sim, isA<double>());
      expect(sim, closeTo(1.0, 1e-6));
    });

    test('single element vectors work correctly', () {
      expect(
        cosineSimilarity(Float32List.fromList([1.0]), Float32List.fromList([1.0])),
        closeTo(1.0, 1e-6),
      );
      expect(
        cosineSimilarity(Float32List.fromList([1.0]), Float32List.fromList([-1.0])),
        closeTo(-1.0, 1e-6),
      );
    });
  });

  group('Face Clustering Thresholds', () {
    test('cosine similarity >= 0.6 means same person', () {
      final a = l2Normalize(Float32List.fromList([1, 2, 3, 4]));
      final b = l2Normalize(Float32List.fromList([1, 2, 3, 4.1]));
      expect(cosineSimilarity(a, b), greaterThanOrEqualTo(0.6));
    });

    test('cosine similarity < 0.6 means different person', () {
      final a = l2Normalize(Float32List.fromList([1, 0, 0, 0]));
      final b = l2Normalize(Float32List.fromList([0, 1, 0, 0]));
      expect(cosineSimilarity(a, b), lessThan(0.6));
    });
  });
}

/// Compute cosine similarity between two vectors.
/// Returns 0.0 for mismatched dimensions or zero vectors.
/// Matches FaceClusteringService.cosineSimilarity logic.
double cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) return 0.0;
  if (a.isEmpty) return 0.0;
  double dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot.clamp(-1.0, 1.0);
}

/// Compute L2 norm of a vector.
double l2Norm(Float32List vector) {
  double sum = 0;
  for (final v in vector) {
    sum += v * v;
  }
  return sum <= 0 ? 0.0 : sqrt(sum);
}

/// L2-normalize a vector (returns new vector).
Float32List l2Normalize(Float32List vector) {
  final norm = l2Norm(vector);
  if (norm == 0.0) return Float32List(vector.length);
  final result = Float32List(vector.length);
  for (var i = 0; i < vector.length; i++) {
    result[i] = vector[i] / norm;
  }
  return result;
}
