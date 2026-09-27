import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

/// Detects whether an image is likely a screenshot.
///
/// Uses multiple heuristics:
/// 1. Aspect ratio (very tall = scroll screenshot)
/// 2. Color palette (few colors, solid backgrounds)
/// 3. Edge patterns (status bar, navigation bar regions)
/// 4. Text density (high text = UI screenshot)
class ScreenshotDetector {
  /// Analyze an image file and return screenshot probability (0.0–1.0).
  Future<double> detectScreenshot(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return 0.0;

      var score = 0.0;
      var factors = 0;

      // Factor 1: Aspect ratio
      final arScore = _aspectRatioScore(image.width, image.height);
      score += arScore;
      factors++;

      // Factor 2: Color analysis
      final colorScore = _colorPaletteScore(image);
      score += colorScore;
      factors++;

      // Factor 3: Edge uniformity
      final edgeScore = _edgeUniformityScore(image);
      score += edgeScore;
      factors++;

      // Factor 4: Content area analysis
      final contentScore = _contentAreaScore(image);
      score += contentScore;
      factors++;

      return factors > 0 ? score / factors : 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Quick check using only metadata (no full decode needed).
  bool quickCheck({
    required int width,
    required int height,
    String? mimeType,
  }) {
    // Common screenshot dimensions (relative to device DPI)
    final ar = width / height;

    // Very tall images are likely scroll screenshots
    if (ar < 0.35) return true;

    // Standard phone screenshots are ~9:16 or ~9:19.5
    if (ar > 0.45 && ar < 0.56) return true;

    return false;
  }

  /// Aspect ratio heuristic.
  double _aspectRatioScore(int w, int h) {
    final ar = w / h;

    // Standard phone screenshot ratios
    if (ar >= 0.46 && ar <= 0.56) return 0.8;
    // Scroll screenshot (very tall)
    if (ar < 0.35) return 0.9;
    // Tablet screenshot
    if (ar >= 0.7 && ar <= 0.78) return 0.6;

    return 0.2;
  }

  /// Color palette analysis.
  ///
  /// Screenshots tend to have large solid-color regions (status bar,
  /// navigation bar, white backgrounds).
  double _colorPaletteScore(img.Image image) {
    // Sample pixels and count unique colors (with quantization)
    final colorCounts = <int, int>{};
    final step = max(1, (image.width * image.height) ~/ 10000);

    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        // Quantize to reduce color space
        final q = ((pixel.r.toInt() >> 4) << 8) |
            ((pixel.g.toInt() >> 4) << 4) |
            (pixel.b.toInt() >> 4);
        colorCounts[q] = (colorCounts[q] ?? 0) + 1;
      }
    }

    // Few dominant colors = likely screenshot
    final total = colorCounts.values.fold(0, (a, b) => a + b);
    final dominantCount = colorCounts.entries
        .where((e) => e.value / total > 0.05)
        .length;

    // 3-8 dominant colors is typical for screenshots
    if (dominantCount >= 2 && dominantCount <= 10) return 0.7;
    if (dominantCount <= 2) return 0.9;

    return 0.2;
  }

  /// Edge uniformity — screenshots have very uniform edges (UI elements).
  double _edgeUniformityScore(img.Image image) {
    // Check top 10% and bottom 10% for uniform horizontal lines
    final topRows = max(1, image.height ~/ 10);
    final bottomStart = image.height - topRows;

    var topUniform = 0.0;
    var bottomUniform = 0.0;

    // Check top rows
    for (var y = 0; y < topRows; y++) {
      final colors = <int>{};
      for (var x = 0; x < image.width; x += max(1, image.width ~/ 20)) {
        final p = image.getPixel(x, y);
        colors.add(p.r.toInt());
      }
      if (colors.length <= 3) topUniform += 1.0;
    }
    topUniform /= topRows;

    // Check bottom rows
    for (var y = bottomStart; y < image.height; y++) {
      final colors = <int>{};
      for (var x = 0; x < image.width; x += max(1, image.width ~/ 20)) {
        final p = image.getPixel(x, y);
        colors.add(p.r.toInt());
      }
      if (colors.length <= 3) bottomUniform += 1.0;
    }
    bottomUniform /= topRows;

    return ((topUniform + bottomUniform) / 2).clamp(0.0, 1.0);
  }

  /// Content area analysis.
  ///
  /// Screenshots often have a large central area with varied content
  /// surrounded by uniform borders (status/nav bars).
  double _contentAreaScore(img.Image image) {
    var borderVariance = 0.0;
    var centerVariance = 0.0;

    // Border pixels
    final borderPixels = <int>[];
    for (var x = 0; x < image.width; x += 5) {
      borderPixels.add(image.getPixel(x, 0).r.toInt());
      borderPixels.add(image.getPixel(x, image.height - 1).r.toInt());
    }
    for (var y = 0; y < image.height; y += 5) {
      borderPixels.add(image.getPixel(0, y).r.toInt());
      borderPixels.add(image.getPixel(image.width - 1, y).r.toInt());
    }

    if (borderPixels.isNotEmpty) {
      final mean = borderPixels.reduce((a, b) => a + b) / borderPixels.length;
      borderVariance = borderPixels
          .map((p) => (p - mean) * (p - mean))
          .reduce((a, b) => a + b) /
          borderPixels.length;
    }

    // Center pixels (skip border region)
    final centerPixels = <int>[];
    final cx = image.width ~/ 2;
    final cy = image.height ~/ 2;
    final sampleSize = min(image.width, image.height) ~/ 4;

    for (var dy = -sampleSize; dy <= sampleSize; dy += 5) {
      for (var dx = -sampleSize; dx <= sampleSize; dx += 5) {
        final px = cx + dx;
        final py = cy + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          centerPixels.add(image.getPixel(px, py).r.toInt());
        }
      }
    }

    if (centerPixels.isNotEmpty) {
      final mean = centerPixels.reduce((a, b) => a + b) / centerPixels.length;
      centerVariance = centerPixels
          .map((p) => (p - mean) * (p - mean))
          .reduce((a, b) => a + b) /
          centerPixels.length;
    }

    // Screenshots have uniform borders and varied center
    if (borderVariance < 50 && centerVariance > 200) return 0.8;
    if (borderVariance < 100) return 0.5;

    return 0.2;
  }
}

/// Result of screenshot detection.
class ScreenshotDetectionResult {
  final bool isScreenshot;
  final double confidence;
  final List<String> reasons;

  const ScreenshotDetectionResult({
    required this.isScreenshot,
    required this.confidence,
    this.reasons = const [],
  });
}
