import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as img;

/// Content and perceptual hashing for duplicate detection.
///
/// Content hash: SHA-256 of file bytes for exact duplicate detection.
/// Perceptual hash: simplified pHash (DCT-based) for near-duplicate detection.
class HashService {
  /// Compute SHA-256 content hash of a file.
  ///
  /// Two files with identical content hashes are byte-identical duplicates.
  Future<String> computeContentHash(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final digest = crypto.sha256.convert(bytes);
    return digest.toString();
  }

  /// Compute perceptual hash of an image file.
  ///
  /// Uses a simplified pHash approach:
  /// 1. Decode to grayscale
  /// 2. Resize to 32x32
  /// 3. Compute DCT
  /// 4. Take top-left 8x8 of DCT
  /// 5. Compute median
  /// 6. Hash: bits above median = 1, below = 0
  ///
  /// Returns hex string of the 64-bit hash.
  /// Two perceptually similar images will have hamming distance < 10.
  Future<String> computePerceptualHash(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return '';

      // Convert to grayscale
      final gray = img.grayscale(image);

      // Resize to 32x32 using area interpolation
      final resized = img.copyResize(
        gray,
        width: 32,
        height: 32,
        interpolation: img.Interpolation.linear,
      );

      // Compute DCT
      final pixels = Float64List(32 * 32);
      for (var y = 0; y < 32; y++) {
        for (var x = 0; x < 32; x++) {
          pixels[y * 32 + x] = resized.getPixel(x, y).r.toDouble();
        }
      }

      final dct = _dct2d(pixels, 32, 32);

      // Take top-left 8x8 (excluding DC component [0,0])
      final lowFreq = Float64List(64);
      var idx = 0;
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          lowFreq[idx++] = dct[y * 32 + x];
        }
      }

      // Compute median (excluding [0,0])
      final values = lowFreq.sublist(1).toList()..sort();
      final median = values[values.length ~/ 2];

      // Generate hash
      var hash = 0;
      for (var i = 0; i < 64; i++) {
        if (lowFreq[i] > median) {
          hash |= (1 << i);
        }
      }

      return hash.toRadixString(16).padLeft(16, '0');
    } catch (_) {
      return '';
    }
  }

  /// Compute hamming distance between two perceptual hashes.
  ///
  /// Returns 0 (identical) to 64 (completely different).
  /// Distance < 10 typically indicates near-duplicate.
  int hammingDistance(String hash1, String hash2) {
    if (hash1.length != hash2.length) return 64;

    final h1 = int.parse(hash1, radix: 16);
    final h2 = int.parse(hash2, radix: 16);
    var xor = h1 ^ h2;
    var distance = 0;

    while (xor != 0) {
      distance++;
      xor &= xor - 1; // Clear lowest set bit
    }

    return distance;
  }

  /// Check if two hashes represent near-duplicates.
  bool isNearDuplicate(
    String hash1,
    String hash2, {
    int maxDistance = 8,
  }) {
    return hammingDistance(hash1, hash2) <= maxDistance;
  }

  /// 2D Discrete Cosine Transform.
  Float64List _dct2d(Float64List input, int width, int height) {
    final temp = Float64List(width * height);
    final output = Float64List(width * height);

    // Row-wise DCT
    for (var y = 0; y < height; y++) {
      for (var u = 0; u < width; u++) {
        var sum = 0.0;
        for (var x = 0; x < width; x++) {
          sum += input[y * width + x] *
              cos((2 * x + 1) * u * pi / (2 * width));
        }
        temp[y * width + u] = sum;
      }
    }

    // Column-wise DCT
    for (var u = 0; u < width; u++) {
      for (var v = 0; v < height; v++) {
        var sum = 0.0;
        for (var y = 0; y < height; y++) {
          sum += temp[y * width + u] *
              cos((2 * y + 1) * v * pi / (2 * height));
        }
        output[v * width + u] = sum;
      }
    }

    return output;
  }
}
