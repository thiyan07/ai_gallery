import 'dart:math';
import 'dart:typed_data';

import '../../../domain/models/analysis_state.dart';

/// Image quality analysis engine.
///
/// Provides blur classification, exposure analysis, and overall quality
/// scoring using pure Dart image processing (no ML required).
class QualityEngine {
  /// Classify blur level using Laplacian variance.
  ///
  /// The Laplacian operator detects edges; low variance means few edges
  /// (i.e., blurry image).
  BlurClassification classifyBlur(Uint8List grayscalePixels, int width, int height) {
    if (grayscalePixels.isEmpty || width < 3 || height < 3) {
      return BlurClassification.unknown;
    }

    final variance = _laplacianVariance(grayscalePixels, width, height);

    if (variance > 500) return BlurClassification.clear;
    if (variance > 200) return BlurClassification.slightlyBlurry;
    if (variance > 50) return BlurClassification.blurry;
    return BlurClassification.veryBlurry;
  }

  /// Classify exposure level using histogram analysis.
  ExposureClassification classifyExposure(Uint8List grayscalePixels) {
    if (grayscalePixels.isEmpty) return ExposureClassification.unknown;

    // Build histogram
    final histogram = List<int>.filled(256, 0);
    for (final pixel in grayscalePixels) {
      histogram[pixel]++;
    }

    final total = grayscalePixels.length;
    final mean = _computeMean(histogram, total);
    final shadowRatio = _computeShadowRatio(histogram, total);
    final highlightRatio = _computeHighlightRatio(histogram, total);

    // Underexposed: mostly dark pixels, low mean
    if (mean < 60 && shadowRatio > 0.7) {
      return ExposureClassification.underexposed;
    }
    if (mean < 85 && shadowRatio > 0.5) {
      return ExposureClassification.slightlyUnderexposed;
    }

    // Overexposed: mostly bright pixels, high mean
    if (mean > 200 && highlightRatio > 0.7) {
      return ExposureClassification.overexposed;
    }
    if (mean > 170 && highlightRatio > 0.5) {
      return ExposureClassification.slightlyOverexposed;
    }

    return ExposureClassification.balanced;
  }

  /// Compute overall quality score (0.0 = worst, 1.0 = best).
  ///
  /// Combines blur, exposure, contrast, and noise metrics.
  double computeQualityScore(
    Uint8List grayscalePixels,
    int width,
    int height, {
    BlurClassification? blurClassification,
    ExposureClassification? exposureClassification,
  }) {
    if (grayscalePixels.isEmpty) return 0.0;

    // Blur score (30% weight)
    final blurVar = _laplacianVariance(grayscalePixels, width, height);
    final blurScore = (blurVar / 1000).clamp(0.0, 1.0) * 0.3;

    // Exposure score (20% weight)
    final expClass = exposureClassification ?? classifyExposure(grayscalePixels);
    final expScore = _exposureToScore(expClass) * 0.2;

    // Contrast score (25% weight)
    final contrast = _computeContrast(grayscalePixels);
    final contrastScore = contrast * 0.25;

    // Noise score (15% weight) — lower noise = higher score
    final noiseLevel = _estimateNoise(grayscalePixels, width, height);
    final noiseScore = (1.0 - noiseLevel).clamp(0.0, 1.0) * 0.15;

    // Brightness distribution score (10% weight)
    final brightnessScore = _computeBrightnessDistribution(grayscalePixels) * 0.1;

    return (blurScore + expScore + contrastScore + noiseScore + brightnessScore)
        .clamp(0.0, 1.0);
  }

  /// Analyze image and return all quality metrics at once.
  QualityAnalysis analyze(
    Uint8List grayscalePixels,
    int width,
    int height,
  ) {
    final blur = classifyBlur(grayscalePixels, width, height);
    final exposure = classifyExposure(grayscalePixels);
    final quality = computeQualityScore(
      grayscalePixels,
      width,
      height,
      blurClassification: blur,
      exposureClassification: exposure,
    );
    final contrast = _computeContrast(grayscalePixels);
    final brightness = _computeMeanBrightness(grayscalePixels);

    return QualityAnalysis(
      blurClassification: blur,
      exposureClassification: exposure,
      qualityScore: quality,
      contrast: contrast,
      brightness: brightness,
    );
  }

  /// Laplacian variance — higher = sharper.
  double _laplacianVariance(Uint8List gray, int w, int h) {
    var sum = 0.0;
    var sumSq = 0.0;
    var count = 0;

    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final center = gray[y * w + x].toDouble();
        final laplacian =
            -4 * center +
            gray[(y - 1) * w + x].toDouble() +
            gray[(y + 1) * w + x].toDouble() +
            gray[y * w + (x - 1)].toDouble() +
            gray[y * w + (x + 1)].toDouble();

        sum += laplacian;
        sumSq += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0) return 0;
    final mean = sum / count;
    return (sumSq / count) - (mean * mean);
  }

  double _computeMean(List<int> histogram, int total) {
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }
    return sum / total;
  }

  double _computeShadowRatio(List<int> histogram, int total) {
    var count = 0;
    for (var i = 0; i < 64; i++) {
      count += histogram[i];
    }
    return count / total;
  }

  double _computeHighlightRatio(List<int> histogram, int total) {
    var count = 0;
    for (var i = 192; i < 256; i++) {
      count += histogram[i];
    }
    return count / total;
  }

  double _exposureToScore(ExposureClassification exposure) {
    switch (exposure) {
      case ExposureClassification.balanced:
        return 1.0;
      case ExposureClassification.slightlyUnderexposed:
      case ExposureClassification.slightlyOverexposed:
        return 0.7;
      case ExposureClassification.underexposed:
      case ExposureClassification.overexposed:
        return 0.3;
      case ExposureClassification.unknown:
        return 0.5;
    }
  }

  /// Contrast: standard deviation of pixel intensities, normalized.
  double _computeContrast(Uint8List gray) {
    if (gray.isEmpty) return 0;

    var sum = 0.0;
    for (final p in gray) {
      sum += p;
    }
    final mean = sum / gray.length;

    var variance = 0.0;
    for (final p in gray) {
      final d = p - mean;
      variance += d * d;
    }
    final stddev = sqrt(variance / gray.length);

    // Normalize: stddev of ~60+ means good contrast
    return (stddev / 80).clamp(0.0, 1.0);
  }

  /// Estimate noise using median absolute deviation of Laplacian.
  double _estimateNoise(Uint8List gray, int w, int h) {
    if (w < 3 || h < 3) return 0;

    final values = <double>[];
    for (var y = 1; y < h - 1; y += 2) {
      for (var x = 1; x < w - 1; x += 2) {
        final center = gray[y * w + x].toDouble();
        final laplacian =
            -4 * center +
            gray[(y - 1) * w + x].toDouble() +
            gray[(y + 1) * w + x].toDouble() +
            gray[y * w + (x - 1)].toDouble() +
            gray[y * w + (x + 1)].toDouble();
        values.add(laplacian.abs());
      }
    }

    if (values.isEmpty) return 0;
    values.sort();
    final median = values[values.length ~/ 2];

    // High noise = high median absolute deviation of Laplacian
    return (median / 50).clamp(0.0, 1.0);
  }

  /// Mean brightness (0–255), normalized to 0.0–1.0.
  double _computeMeanBrightness(Uint8List gray) {
    if (gray.isEmpty) return 0.5;
    var sum = 0;
    for (final p in gray) {
      sum += p;
    }
    return (sum / gray.length) / 255.0;
  }

  /// How well-distributed brightness values are.
  double _computeBrightnessDistribution(Uint8List gray) {
    if (gray.isEmpty) return 0;

    final histogram = List<int>.filled(256, 0);
    for (final p in gray) {
      histogram[p]++;
    }

    // Check if values span most of the 0–255 range
    var minBin = 255;
    var maxBin = 0;
    for (var i = 0; i < 256; i++) {
      if (histogram[i] > 0) {
        if (i < minBin) minBin = i;
        if (i > maxBin) maxBin = i;
      }
    }

    final range = (maxBin - minBin) / 255.0;

    // Good distribution = range spans > 60% of available range
    return range.clamp(0.0, 1.0);
  }
}

/// Combined quality analysis results.
class QualityAnalysis {
  final BlurClassification blurClassification;
  final ExposureClassification exposureClassification;
  final double qualityScore;
  final double contrast;
  final double brightness;

  const QualityAnalysis({
    required this.blurClassification,
    required this.exposureClassification,
    required this.qualityScore,
    required this.contrast,
    required this.brightness,
  });

  QualityAnalysis copyWith({
    BlurClassification? blurClassification,
    ExposureClassification? exposureClassification,
    double? qualityScore,
    double? contrast,
    double? brightness,
  }) {
    return QualityAnalysis(
      blurClassification: blurClassification ?? this.blurClassification,
      exposureClassification:
          exposureClassification ?? this.exposureClassification,
      qualityScore: qualityScore ?? this.qualityScore,
      contrast: contrast ?? this.contrast,
      brightness: brightness ?? this.brightness,
    );
  }
}
