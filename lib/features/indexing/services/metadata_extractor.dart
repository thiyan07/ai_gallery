import 'dart:math';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

import '../../../domain/models/photo_metadata.dart';
import '../../../core/logging/app_logger.dart';

/// Service for extracting metadata from photos.
class MetadataExtractor {
  MetadataExtractor({
    required AppLogger logger,
  }) : _logger = logger;

  final AppLogger _logger;

  /// Extracts metadata from an AssetEntity.
  Future<PhotoMetadata> extractFromAsset(
    AssetEntity asset, {
    bool includeAnalysis = false,
  }) async {
    final file = await asset.originFile;
    if (file == null) {
      _logger.warning('Could not get origin file for asset: ${asset.id}');
      return _basicMetadata(asset);
    }

    final bytes = await file.readAsBytes();
    final fileSizeBytes = bytes.length;

    // Extract EXIF data
    final exifData = await _readExif(bytes);

    // Extract color analysis and quality metrics
    final colorAnalysis = _analyzeColors(bytes);
    final qualityMetrics = _analyzeQuality(bytes);

    // Parse EXIF fields
    final cameraMake = _getExifString(exifData, 'Image Make') ??
        _getExifString(exifData, 'EXIF Make');
    final cameraModel = _getExifString(exifData, 'Image Model') ??
        _getExifString(exifData, 'EXIF Model');
    final iso = _getExifInt(exifData, 'EXIF ISOSpeedRatings');
    final shutterSpeed = _getExifRational(exifData, 'EXIF ExposureTime');
    final aperture = _getExifRational(exifData, 'EXIF FNumber');
    final orientation = _getExifInt(exifData, 'Image Orientation') ?? 0;
    final dateCreated = _parseExifDate(exifData, 'EXIF DateTimeOriginal') ??
        asset.createDateTime;
    final dateModified = _parseExifDate(exifData, 'EXIF DateTimeDigitized') ??
        asset.modifiedDateTime;

    return PhotoMetadata(
      photoId: asset.id,
      width: asset.width,
      height: asset.height,
      fileSizeBytes: fileSizeBytes,
      mimeType: asset.mimeType,
      dateCreated: dateCreated,
      dateModified: dateModified,
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      iso: iso,
      shutterSpeed: shutterSpeed,
      aperture: aperture,
      latitude: asset.latitude,
      longitude: asset.longitude,
      orientation: orientation,
      dominantColor: colorAnalysis.dominantColor,
      averageColor: colorAnalysis.averageColor,
      brightness: colorAnalysis.brightness,
      contrast: colorAnalysis.contrast,
      blurScore: qualityMetrics.blurScore,
      qualityScore: qualityMetrics.qualityScore,
      indexedAt: DateTime.now(),
      mediaType: asset.type == AssetType.video ? 'video' : 'image',
      durationSeconds: asset.type == AssetType.video ? asset.duration : 0,
    );
  }

  /// Basic metadata fallback when file access fails.
  PhotoMetadata _basicMetadata(AssetEntity asset) {
    return PhotoMetadata(
      photoId: asset.id,
      width: asset.width,
      height: asset.height,
      fileSizeBytes: 0,
      mimeType: asset.mimeType,
      dateCreated: asset.createDateTime,
      dateModified: asset.modifiedDateTime,
      cameraMake: null,
      cameraModel: null,
      iso: null,
      shutterSpeed: null,
      aperture: null,
      latitude: asset.latitude,
      longitude: asset.longitude,
      orientation: 0,
      dominantColor: null,
      averageColor: null,
      brightness: null,
      contrast: null,
      blurScore: null,
      qualityScore: null,
      indexedAt: DateTime.now(),
      mediaType: asset.type == AssetType.video ? 'video' : 'image',
      durationSeconds: asset.type == AssetType.video ? asset.duration : 0,
    );
  }

  /// Read EXIF data from image bytes.
  Future<Map<String, IfdTag>> _readExif(Uint8List bytes) async {
    try {
      return await readExifFromBytes(bytes);
    } catch (e, st) {
      _logger.warning('Failed to read EXIF data', error: e, stackTrace: st);
      return {};
    }
  }

  /// Get string value from EXIF entry.
  String? _getExifString(Map<String, IfdTag> exif, String tag) {
    final entry = exif[tag];
    if (entry == null) return null;
    final value = entry.printable.trim();
    return value.isEmpty ? null : value;
  }

  /// Get integer value from EXIF entry.
  int? _getExifInt(Map<String, IfdTag> exif, String tag) {
    final entry = exif[tag];
    if (entry == null) return null;
    try {
      final values = entry.values.toList();
      if (values.isNotEmpty && values[0] is int) {
        return values[0] as int;
      }
      return int.tryParse(values[0].toString());
    } catch (_) {
      return null;
    }
  }

  /// Get rational (fraction) value as double from EXIF entry.
  double? _getExifRational(Map<String, IfdTag> exif, String tag) {
    final entry = exif[tag];
    if (entry == null) return null;
    try {
      final values = entry.values.toList();
      if (values.isNotEmpty && values[0] is Ratio) {
        final ratio = values[0] as Ratio;
        return ratio.toDouble();
      }
      return double.tryParse(entry.printable);
    } catch (_) {
      return null;
    }
  }

  /// Parse EXIF date string to DateTime.
  DateTime? _parseExifDate(Map<String, IfdTag> exif, String tag) {
    final entry = exif[tag];
    if (entry == null) return null;
    try {
      // EXIF format: "YYYY:MM:DD HH:MM:SS"
      final str = entry.printable.trim();
      return DateTime.parse(str.replaceFirst(':', '-').replaceFirst(':', '-'));
    } catch (_) {
      return null;
    }
  }

  /// Analyze image colors and compute statistics.
  _ColorAnalysis _analyzeColors(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return _ColorAnalysis.empty();

      // Resize for faster analysis (max 100x100)
      final analysisImage = img.copyResize(image, width: 100, height: 100);

      // Compute histogram for dominant color
      final histogram = <int, int>{};
      int rSum = 0, gSum = 0, bSum = 0;
      int pixelCount = 0;

      for (int y = 0; y < analysisImage.height; y++) {
        for (int x = 0; x < analysisImage.width; x++) {
          final pixel = analysisImage.getPixel(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();

          // Quantize to 8 levels per channel (512 colors)
          final key = ((r >> 5) << 16) | ((g >> 5) << 8) | (b >> 5);
          histogram[key] = (histogram[key] ?? 0) + 1;

          rSum += r;
          gSum += g;
          bSum += b;
          pixelCount++;
        }
      }

      // Find dominant color
      int dominantKey = 0;
      int maxCount = 0;
      histogram.forEach((key, count) {
        if (count > maxCount) {
          maxCount = count;
          dominantKey = key;
        }
      });

      final dominantR = (dominantKey >> 16) & 0xFF;
      final dominantG = (dominantKey >> 8) & 0xFF;
      final dominantB = dominantKey & 0xFF;

      // Compute average color
      final avgR = (rSum / pixelCount).round();
      final avgG = (gSum / pixelCount).round();
      final avgB = (bSum / pixelCount).round();

      // Compute brightness (luminance)
      final brightness = (0.299 * avgR + 0.587 * avgG + 0.114 * avgB) / 255.0;

      // Compute contrast (RMS contrast)
      double contrast = 0;
      for (int y = 0; y < analysisImage.height; y++) {
        for (int x = 0; x < analysisImage.width; x++) {
          final pixel = analysisImage.getPixel(x, y);
          final luminance = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
          contrast += (luminance - brightness * 255) * (luminance - brightness * 255);
        }
      }
      contrast = sqrt(contrast / pixelCount) / 255.0;

      return _ColorAnalysis(
        dominantColor: (dominantR << 16) | (dominantG << 8) | dominantB,
        averageColor: (avgR << 16) | (avgG << 8) | avgB,
        brightness: brightness,
        contrast: contrast.clamp(0.0, 1.0),
      );
    } catch (e, st) {
      _logger.warning('Color analysis failed', error: e, stackTrace: st);
      return _ColorAnalysis.empty();
    }
  }

  /// Analyze image quality (blur detection, noise, etc.).
  _QualityMetrics _analyzeQuality(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return _QualityMetrics.empty();

      // Convert to grayscale for blur detection
      final gray = img.grayscale(image);

      // Resize to fixed size for consistent blur detection
      final resized = img.copyResize(gray, width: 224, height: 224);

      // Compute Laplacian variance (blur score)
      double laplacianVariance = _computeLaplacianVariance(resized);

      // Normalize: higher variance = sharper = lower blur score
      // Typical range: 0 (very blurry) to 1000+ (sharp)
      // We normalize to 0-1 where 0 = sharp, 1 = blurry
      final blurScore = (1.0 - (laplacianVariance / 1000.0)).clamp(0.0, 1.0);

      // Quality score: combination of sharpness, exposure, noise
      // Simple heuristic: inverse of blur score
      final qualityScore = (1.0 - blurScore).clamp(0.0, 1.0);

      return _QualityMetrics(
        blurScore: blurScore,
        qualityScore: qualityScore,
      );
    } catch (e, st) {
      _logger.warning('Quality analysis failed', error: e, stackTrace: st);
      return _QualityMetrics.empty();
    }
  }

  /// Compute Laplacian variance for blur detection.
  double _computeLaplacianVariance(img.Image grayImage) {
    const kernel = [
      [0, 1, 0],
      [1, -4, 1],
      [0, 1, 0],
    ];

    double sum = 0;
    double sumSq = 0;
    int count = 0;

    for (int y = 1; y < grayImage.height - 1; y++) {
      for (int x = 1; x < grayImage.width - 1; x++) {
        double lap = 0;
        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final pixel = grayImage.getPixel(x + kx, y + ky);
            lap += pixel.r * kernel[ky + 1][kx + 1];
          }
        }
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }

    final mean = sum / count;
    return (sumSq / count) - (mean * mean);
  }
}

class _ColorAnalysis {
  final int? dominantColor;
  final int? averageColor;
  final double? brightness;
  final double? contrast;

  const _ColorAnalysis({
    this.dominantColor,
    this.averageColor,
    this.brightness,
    this.contrast,
  });

  factory _ColorAnalysis.empty() => const _ColorAnalysis();
}

class _QualityMetrics {
  final double? blurScore;
  final double? qualityScore;

  const _QualityMetrics({this.blurScore, this.qualityScore});

  factory _QualityMetrics.empty() => const _QualityMetrics();
}