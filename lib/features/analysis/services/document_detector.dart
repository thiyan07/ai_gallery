import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

/// Detects whether an image is likely a document, receipt, or text-heavy photo.
///
/// Uses heuristics based on:
/// 1. Aspect ratio (A4, letter size)
/// 2. High contrast text regions
/// 3. Edge density (document edges)
/// 4. Color distribution (mostly white/light background)
class DocumentDetector {
  /// Analyze an image file and return document probability (0.0–1.0).
  Future<double> detectDocument(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return 0.0;

      var score = 0.0;
      var factors = 0;

      // Factor 1: Aspect ratio (A4/letter/document)
      final arScore = _aspectRatioScore(image.width, image.height);
      score += arScore;
      factors++;

      // Factor 2: Background whiteness
      final bgScore = _backgroundWhitenessScore(image);
      score += bgScore;
      factors++;

      // Factor 3: Text edge density
      final edgeScore = _textEdgeDensity(image);
      score += edgeScore;
      factors++;

      // Factor 4: Color uniformity (documents are usually B&W or grayscale-ish)
      final colorScore = _colorUniformityScore(image);
      score += colorScore;
      factors++;

      return factors > 0 ? score / factors : 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Quick check using metadata only.
  bool quickCheck({
    required int width,
    required int height,
  }) {
    final ar = width / height;

    // A4: 210mm x 297mm ≈ 0.707
    // Letter: 216mm x 279mm ≈ 0.774
    // Common document scan ratios
    if (ar >= 0.65 && ar <= 0.82) return true;
    if (ar >= 1.2 && ar <= 1.55) return true; // Landscape A4

    return false;
  }

  double _aspectRatioScore(int w, int h) {
    final ar = w / h;
    final invAr = h / w;

    // A4 ratio ≈ 0.707
    if ((ar - 0.707).abs() < 0.1) return 0.9;
    if ((invAr - 0.707).abs() < 0.1) return 0.9;

    // Letter ratio ≈ 0.774
    if ((ar - 0.774).abs() < 0.1) return 0.85;
    if ((invAr - 0.774).abs() < 0.1) return 0.85;

    // Other common document ratios
    if (ar >= 0.65 && ar <= 0.85) return 0.6;
    if (invAr >= 0.65 && invAr <= 0.85) return 0.6;

    return 0.1;
  }

  /// How white/light the dominant background is.
  double _backgroundWhitenessScore(img.Image image) {
    var lightCount = 0;
    var totalCount = 0;
    final step = max(1, (image.width * image.height) ~/ 10000);

    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final p = image.getPixel(x, y);
        final brightness = (p.r + p.g + p.b) / 3;
        if (brightness > 200) lightCount++;
        totalCount++;
      }
    }

    final ratio = totalCount > 0 ? lightCount / totalCount : 0;

    // Documents are usually 60-90% white/light
    if (ratio > 0.6 && ratio < 0.95) return 0.8;
    if (ratio > 0.4) return 0.5;
    if (ratio > 0.85) return 0.6; // Almost all white = possible blank page

    return 0.2;
  }

  /// High text edge density suggests text-heavy content.
  double _textEdgeDensity(img.Image image) {
    // Convert to grayscale and find horizontal edges (text lines)
    var horizontalEdges = 0;
    var totalChecks = 0;

    final step = max(1, image.height ~/ 50);
    final xStep = max(1, image.width ~/ 50);

    for (var y = step; y < image.height - step; y += step) {
      for (var x = xStep; x < image.width - xStep; x += xStep) {
        final top = image.getPixel(x, y - 1).r.toInt();
        final center = image.getPixel(x, y).r.toInt();
        final diff = (top - center).abs();

        if (diff > 30) horizontalEdges++;
        totalChecks++;
      }
    }

    final density = totalChecks > 0 ? horizontalEdges / totalChecks : 0;

    // Documents have moderate horizontal edge density (text lines)
    if (density > 0.1 && density < 0.5) return 0.7;
    if (density > 0.05) return 0.4;

    return 0.1;
  }

  /// Documents tend to have low color variance (mostly grayscale/B&W).
  double _colorUniformityScore(img.Image image) {
    var rSum = 0.0;
    var gSum = 0.0;
    var bSum = 0.0;
    var rVar = 0.0;
    var gVar = 0.0;
    var bVar = 0.0;
    var count = 0;

    final step = max(1, (image.width * image.height) ~/ 10000);

    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final p = image.getPixel(x, y);
        rSum += p.r;
        gSum += p.g;
        bSum += p.b;
        count++;
      }
    }

    if (count == 0) return 0;

    final rMean = rSum / count;
    final gMean = gSum / count;
    final bMean = bSum / count;

    // Now compute variance
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final p = image.getPixel(x, y);
        rVar += (p.r - rMean) * (p.r - rMean);
        gVar += (p.g - gMean) * (p.g - gMean);
        bVar += (p.b - bMean) * (p.b - bMean);
      }
    }

    rVar /= count;
    gVar /= count;
    bVar /= count;

    // Documents have low color variance and channels are close
    final totalVariance = rVar + gVar + bVar;
    final channelDiff = (rMean - gMean).abs() + (gMean - bMean).abs();

    // Low variance = grayscale-ish = likely document
    if (totalVariance < 2000 && channelDiff < 30) return 0.8;
    if (totalVariance < 5000) return 0.5;

    return 0.2;
  }
}
